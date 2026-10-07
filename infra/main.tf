provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { project = var.project, env = var.env, owner = var.owner }
  }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
locals {
  name = "${var.project}-${var.env}"
  lake = "${local.name}-lake-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}
resource "aws_s3_bucket" "lake" {
  bucket        = local.lake
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "lake" {
  bucket = aws_s3_bucket.lake.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  dynamic "rule" {
    for_each = toset(["raw/", "curated/"])
    content {
      id     = "expire-${trimsuffix(rule.value, "/")}"
      status = "Enabled"
      filter { prefix = rule.value }
      expiration { days = 7 }
      abort_incomplete_multipart_upload { days_after_initiation = 1 }
    }
  }
}
resource "aws_glue_catalog_database" "clickstream" {
  name = replace(local.name, "-", "_")
}
resource "aws_kinesis_stream" "events" {
  count            = var.enable_stream ? 1 : 0
  name             = "${local.name}-events"
  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"
  stream_mode_details { stream_mode = "ON_DEMAND" }
}
resource "aws_cloudwatch_log_group" "flink" {
  name              = "/aws/kinesis-analytics/${local.name}"
  retention_in_days = 3
}
resource "aws_iam_role" "producer" {
  name = "${local.name}-producer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { AWS = var.producer_principal_arn }
    }]
  })
}
resource "aws_iam_role_policy" "producer" {
  name = "write-project-stream"
  role = aws_iam_role.producer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStreamSummary"]
      Resource = "arn:${data.aws_partition.current.partition}:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/${local.name}-events"
    }]
  })
}
