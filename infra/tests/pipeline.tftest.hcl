mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:role/operator", user_id = "test" }
  }
  mock_data "aws_partition" { defaults = { partition = "aws", dns_suffix = "amazonaws.com" } }
}
variables {
  project_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/ClickstreamProjectBoundary"
  owner                            = "test-owner"
  budget_email                     = "test@example.com"
  producer_principal_arn           = "arn:aws:iam::123456789012:role/operator"
  flink_jar_path                   = "tests/fixture.txt"
}
run "pipeline_is_opt_in" {
  command = plan
  assert {
    condition     = length(aws_kinesisanalyticsv2_application.pipeline) == 0 && length(aws_athena_workgroup.demo) == 0
    error_message = "Default plans must not create pipeline resources."
  }
}
run "pipeline_requires_stream" {
  command = plan
  variables { enable_pipeline = true }
  expect_failures = [var.enable_pipeline]
}
run "bounded_pipeline" {
  command = plan
  variables {
    enable_pipeline = true
    enable_stream   = true
  }
  assert {
    condition     = aws_iam_role.flink[0].permissions_boundary == var.project_permissions_boundary_arn
    error_message = "Flink must retain the administrator-managed boundary."
  }
  assert {
    condition     = !one(one(aws_kinesisanalyticsv2_application.pipeline[0].application_configuration).flink_application_configuration).parallelism_configuration[0].auto_scaling_enabled
    error_message = "Demo must disable autoscaling."
  }
  assert {
    condition     = one(aws_athena_workgroup.demo[0].configuration).bytes_scanned_cutoff_per_query == 10485760 && one(aws_athena_workgroup.demo[0].configuration).enforce_workgroup_configuration
    error_message = "Every query must respect the enforced workgroup scan cap."
  }
  assert {
    condition     = alltrue([for rule in aws_s3_bucket_lifecycle_configuration.lake.rule : !contains(["iceberg/", "curated/"], one(rule.filter).prefix)])
    error_message = "S3 expiration must never delete Iceberg table files."
  }
  assert {
    condition     = jsondecode(aws_iam_role.flink[0].assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:kinesisanalytics:us-west-2:123456789012:application/clickstream-dev-pipeline"
    error_message = "Flink trust must be constrained to the exact application."
  }
}
