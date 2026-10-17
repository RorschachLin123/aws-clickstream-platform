# Account-wide budget: intentionally includes untagged and delayed-tag costs.
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  dynamic "notification" {
    for_each = toset([50, 80, 100])
    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = "ACTUAL"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
resource "aws_iam_policy" "budget_deny" {
  name = "${local.name}-budget-deny-input"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords"]
      Resource = "arn:${data.aws_partition.current.partition}:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/${local.name}-events"
    }]
  })
}
resource "aws_iam_role" "budgets" {
  permissions_boundary = var.project_permissions_boundary_arn
  name                 = "${local.name}-budgets-action"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "budgets.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:budgets::${data.aws_caller_identity.current.account_id}:budget/${aws_budgets_budget.monthly.name}" }
      }
    }]
  })
}
resource "aws_iam_role_policy" "budgets" {
  name = "attach-only-project-deny"
  role = aws_iam_role.budgets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
      Resource  = aws_iam_role.producer.arn
      Condition = { ArnEquals = { "iam:PolicyARN" = aws_iam_policy.budget_deny.arn } }
    }]
  })
}
resource "aws_budgets_budget_action" "deny_input" {
  budget_name        = aws_budgets_budget.monthly.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets.arn
  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }
  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.budget_deny.arn
      roles      = [aws_iam_role.producer.name]
    }
  }
  subscriber {
    address           = var.budget_email
    subscription_type = "EMAIL"
  }
  depends_on = [aws_iam_role_policy.budgets]
}
