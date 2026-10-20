variable "enable_deadline_guard" {
  description = "Opt-in independent cloud stop deadline for the disposable pipeline."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_deadline_guard || var.enable_pipeline
    error_message = "Deadline guard requires enable_pipeline=true."
  }
}
variable "demo_stop_at" {
  description = "Absolute UTC stop deadline, RFC3339; refresh the reviewed plan before each demo."
  type        = string
  default     = "2099-01-01T00:00:00Z"
  validation {
    condition     = can(formatdate("YYYY-MM-DD'T'hh:mm:ss", var.demo_stop_at)) && endswith(var.demo_stop_at, "Z")
    error_message = "demo_stop_at must be an RFC3339 UTC timestamp ending in Z."
  }
}
locals {
  deadline_count     = var.enable_deadline_guard ? 1 : 0
  deadline_group_arn = "arn:${data.aws_partition.current.partition}:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule-group/${local.name}-demo"
}
resource "aws_scheduler_schedule_group" "demo" {
  count = local.deadline_count
  name  = "${local.name}-demo"
}
resource "aws_iam_role" "deadline" {
  count                = local.deadline_count
  name                 = "${local.name}-deadline"
  permissions_boundary = var.project_permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
      Condition = { StringEquals = {
        "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        "aws:SourceArn"     = local.deadline_group_arn
      } }
    }]
  })
}
resource "aws_iam_role_policy" "deadline" {
  count = local.deadline_count
  name  = "stop-only-demo-application"
  role  = aws_iam_role.deadline[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "kinesisanalytics:StopApplication", Resource = local.flink_app_arn }]
  })
}
resource "aws_scheduler_schedule" "stop" {
  count                        = local.deadline_count
  name                         = "${local.name}-stop"
  group_name                   = aws_scheduler_schedule_group.demo[0].name
  schedule_expression          = "at(${formatdate("YYYY-MM-DD'T'hh:mm:ss", var.demo_stop_at)})"
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"
  action_after_completion      = "NONE"
  flexible_time_window { mode = "OFF" }
  target {
    arn      = "arn:${data.aws_partition.current.partition}:scheduler:::aws-sdk:kinesisanalyticsv2:stopApplication"
    role_arn = aws_iam_role.deadline[0].arn
    input    = jsonencode({ ApplicationName = "${local.name}-pipeline", Force = true })
    retry_policy {
      maximum_event_age_in_seconds = 300
      maximum_retry_attempts       = 3
    }
  }
  depends_on = [aws_kinesisanalyticsv2_application.pipeline, aws_iam_role_policy.deadline]
}
