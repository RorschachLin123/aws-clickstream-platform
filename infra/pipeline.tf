variable "enable_pipeline" {
  description = "Opt-in Managed Flink/Iceberg/Athena demo; requires enable_stream."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_pipeline || var.enable_stream
    error_message = "enable_pipeline requires enable_stream=true."
  }
}
variable "flink_jar_path" {
  description = "Local, tested shaded JAR. Required only for pipeline plans."
  type        = string
  default     = "../flink/target/clickstream-flink.jar"
}
locals {
  pipeline_count = var.enable_pipeline ? 1 : 0
  glue_catalog   = "arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog"
  glue_database  = "arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.clickstream.name}"
  glue_table     = "arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.clickstream.name}/events"
  flink_app_arn  = "arn:${data.aws_partition.current.partition}:kinesisanalytics:${var.aws_region}:${data.aws_caller_identity.current.account_id}:application/${local.name}-pipeline"
}
resource "aws_s3_object" "flink_jar" {
  count                  = local.pipeline_count
  bucket                 = aws_s3_bucket.lake.id
  key                    = "artifacts/${filesha256(var.flink_jar_path)}/clickstream-flink.jar"
  source                 = var.flink_jar_path
  source_hash            = filesha256(var.flink_jar_path)
  server_side_encryption = "AES256"
}
resource "aws_cloudwatch_log_stream" "flink" {
  count          = local.pipeline_count
  name           = "application"
  log_group_name = aws_cloudwatch_log_group.flink.name
}
resource "aws_iam_role" "flink" {
  count                = local.pipeline_count
  name                 = "${local.name}-flink"
  permissions_boundary = var.project_permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "kinesisanalytics.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = local.flink_app_arn }
      }
    }]
  })
}
resource "aws_iam_role_policy" "flink" {
  count = local.pipeline_count
  name  = "read-stream-write-iceberg"
  role  = aws_iam_role.flink[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListShards", "kinesis:GetShardIterator", "kinesis:GetRecords"], Resource = aws_kinesis_stream.events[0].arn },
      { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = aws_s3_bucket.lake.arn },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.lake.arn}/artifacts/*" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"], Resource = "${aws_s3_bucket.lake.arn}/iceberg/*" },
      { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:CreateTable", "glue:UpdateTable"], Resource = [local.glue_catalog, local.glue_database, local.glue_table] },
      { Effect = "Allow", Action = ["logs:PutLogEvents"], Resource = aws_cloudwatch_log_stream.flink[0].arn },
      { Effect = "Allow", Action = ["logs:DescribeLogStreams"], Resource = aws_cloudwatch_log_group.flink.arn },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*" }
    ]
  })
}
resource "aws_kinesisanalyticsv2_application" "pipeline" {
  count                  = local.pipeline_count
  name                   = "${local.name}-pipeline"
  runtime_environment    = "FLINK-1_20"
  service_execution_role = aws_iam_role.flink[0].arn
  application_configuration {
    application_code_configuration {
      code_content_type = "ZIPFILE"
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.lake.arn
          file_key   = aws_s3_object.flink_jar[0].key
        }
      }
    }
    environment_properties {
      property_group {
        property_group_id = "Pipeline"
        property_map = {
          region     = var.aws_region
          stream_arn = aws_kinesis_stream.events[0].arn
          warehouse  = "s3://${aws_s3_bucket.lake.id}/iceberg/"
          database   = aws_glue_catalog_database.clickstream.name
          table      = "events"
        }
      }
    }
    flink_application_configuration {
      checkpoint_configuration {
        configuration_type            = "CUSTOM"
        checkpointing_enabled         = true
        checkpoint_interval           = 30000
        min_pause_between_checkpoints = 10000
      }
      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        auto_scaling_enabled = false
        parallelism          = 1
        parallelism_per_kpu  = 1
      }
    }
    application_snapshot_configuration { snapshots_enabled = false }
  }
  cloudwatch_logging_options { log_stream_arn = aws_cloudwatch_log_stream.flink[0].arn }
  depends_on = [aws_iam_role_policy.flink, aws_s3_bucket_policy.lake, aws_s3_bucket_public_access_block.lake]
}
resource "aws_athena_workgroup" "demo" {
  count         = local.pipeline_count
  name          = "${local.name}-demo"
  force_destroy = false
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10485760
    engine_version { selected_engine_version = "Athena engine version 3" }
    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.id}/query-results/"
      encryption_configuration { encryption_option = "SSE_S3" }
    }
  }
}
output "flink_application" { value = try(aws_kinesisanalyticsv2_application.pipeline[0].name, null) }
output "athena_workgroup" { value = try(aws_athena_workgroup.demo[0].name, null) }
