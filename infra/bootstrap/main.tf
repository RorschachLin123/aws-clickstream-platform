terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}
provider "aws" {
  region = var.aws_region
  default_tags { tags = { project = var.project, env = var.env, owner = var.owner } }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
resource "random_id" "suffix" { byte_length = 4 }
locals {
  name = "${var.project}-${var.env}"
  oidc = var.existing_oidc_provider_arn != null ? var.existing_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
  lake = "${local.name}-lake-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}
resource "aws_s3_bucket" "state" {
  bucket        = "${local.name}-tfstate-${random_id.suffix.hex}"
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_iam_role" "ci_plan" {
  name = "${local.name}-ci-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = var.github_oidc_subject
        }
      }
    }]
  })
}
# Read-only cloud access, plus state locks. No CI apply or deployment permissions.
resource "aws_iam_role_policy" "ci_plan" {
  name = "read-project-and-lock-state"
  role = aws_iam_role.ci_plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.state.arn },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.state.arn}/clickstream/dev/terraform.tfstate" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.state.arn}/clickstream/dev/terraform.tfstate.tflock" },
      { Effect = "Allow", Action = ["s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration", "s3:GetAccelerateConfiguration", "s3:ListBucket"], Resource = "arn:${data.aws_partition.current.partition}:s3:::${local.lake}" },
      { Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListTagsForStream", "kinesis:ListTagsForResource"], Resource = "arn:${data.aws_partition.current.partition}:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/${local.name}-events" },
      { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTags"], Resource = ["arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog", "arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${replace(local.name, "-", "_")}"] },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups", "budgets:ViewBudget", "budgets:Describe*", "budgets:ListTagsForResource"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:ListTagsForResource", "logs:ListTagsLogGroup"], Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesis-analytics/${local.name}:*" },
      { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"], Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-*" },
      { Effect = "Allow", Action = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListPolicyTags"], Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${local.name}-*" }
    ]
  })
}
output "state_bucket" { value = aws_s3_bucket.state.id }
output "ci_role_arn" { value = aws_iam_role.ci_plan.arn }
