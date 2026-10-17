mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:role/operator", user_id = "test" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
}
variables {
  project_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/ClickstreamProjectBoundary"
  owner                            = "test-owner"
  budget_email                     = "test@example.com"
  producer_principal_arn           = "arn:aws:iam::123456789012:role/operator"
}
run "default_is_not_billable_stream" {
  command = plan
  assert {
    condition     = aws_iam_role.producer.permissions_boundary == var.project_permissions_boundary_arn && aws_iam_role.budgets.permissions_boundary == var.project_permissions_boundary_arn
    error_message = "Every Terraform-created IAM role must retain the project boundary."
  }
  assert {
    condition     = length(aws_kinesis_stream.events) == 0
    error_message = "Default plans must not create a billable Kinesis stream."
  }
  assert {
    condition     = aws_s3_bucket.lake.force_destroy == false && aws_s3_bucket_public_access_block.lake.block_public_policy
    error_message = "Lake deletion must be deliberate and public access blocked."
  }
  assert {
    condition     = aws_cloudwatch_log_group.flink.retention_in_days == 3
    error_message = "Logs must expire after 3 days."
  }
  assert {
    condition     = aws_budgets_budget_action.deny_input.approval_model == "AUTOMATIC" && one(aws_budgets_budget_action.deny_input.action_threshold).action_threshold_value == 100
    error_message = "Budget action must trigger automatically at 100 percent."
  }
}
run "demo_stream_is_opt_in" {
  command = plan
  variables { enable_stream = true }
  assert {
    condition     = length(aws_kinesis_stream.events) == 1 && aws_kinesis_stream.events[0].encryption_type == "KMS" && one(aws_kinesis_stream.events[0].stream_mode_details).stream_mode == "ON_DEMAND"
    error_message = "Demo must provision one encrypted on-demand stream."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.producer.policy).Statement[0].Resource == "arn:aws:kinesis:us-west-2:123456789012:stream/clickstream-dev-events"
    error_message = "Producer writes must be scoped to the project stream."
  }
}
run "invalid_budget_rejected" {
  command = plan
  variables { monthly_budget_usd = 0 }
  expect_failures = [var.monthly_budget_usd]
}
