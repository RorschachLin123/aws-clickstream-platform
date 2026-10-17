variable "aws_region" {
  type    = string
  default = "us-west-2"
}
variable "project" {
  type    = string
  default = "clickstream"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project))
    error_message = "Use 3-25 lowercase letters, numbers or hyphens."
  }
}
variable "env" {
  type    = string
  default = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,9}$", var.env))
    error_message = "Use 2-10 lowercase letters, numbers or hyphens."
  }
}
variable "owner" { type = string }
variable "github_oidc_subject" {
  description = "Exact main-branch subject from repository OIDC settings; supports immutable IDs."
  type        = string
  validation {
    condition     = can(regex("^repo:[^*? :]+/[^*? :]+:ref:refs/heads/main$", var.github_oidc_subject))
    error_message = "Use the exact repo main-branch subject without wildcards."
  }
}
variable "existing_oidc_provider_arn" {
  description = "If GitHub OIDC provider already exists in this AWS account, reuse its ARN."
  type        = string
  default     = null
}

variable "project_permissions_boundary_arn" {
  description = "Root-managed boundary required on Terraform-created project roles."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/ClickstreamProjectBoundary$", var.project_permissions_boundary_arn))
    error_message = "Use the root-managed ClickstreamProjectBoundary ARN."
  }
}
