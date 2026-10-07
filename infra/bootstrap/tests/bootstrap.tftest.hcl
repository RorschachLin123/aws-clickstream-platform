mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
}
mock_provider "random" {}
variables {
  owner               = "test-owner"
  github_oidc_subject = "repo:owner@123/repo@456:ref:refs/heads/main"
}
run "exact_trust_and_versioned_state" {
  command = plan
  variables { existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  assert {
    condition     = jsondecode(aws_iam_role.ci_plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == var.github_oidc_subject
    error_message = "CI trust must preserve the exact main-branch subject, including immutable IDs."
  }
  assert {
    condition     = one(aws_s3_bucket_versioning.state.versioning_configuration).status == "Enabled" && aws_s3_bucket.state.force_destroy == false
    error_message = "State must be versioned and never force-deleted."
  }
}
run "reuse_shared_oidc_provider" {
  command = plan
  variables { existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "Shared provider must not be recreated."
  }
}
run "wildcard_subject_rejected" {
  command = plan
  variables { github_oidc_subject = "repo:owner/*:ref:refs/heads/main" }
  expect_failures = [var.github_oidc_subject]
}
run "pr_subject_rejected" {
  command = plan
  variables { github_oidc_subject = "repo:owner/repo:pull_request" }
  expect_failures = [var.github_oidc_subject]
}

run "create_oidc_when_not_shared" {
  command = plan
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "Create the provider when no shared provider was supplied."
  }
}
