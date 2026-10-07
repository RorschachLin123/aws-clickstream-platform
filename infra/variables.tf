variable "aws_region" {
  type    = string
  default = "us-west-2"
}
variable "project" {
  type    = string
  default = "clickstream"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project))
    error_message = "Use 3-25 lowercase letters, numbers or hyphens, starting with a letter."
  }
}
variable "env" {
  type    = string
  default = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,9}$", var.env))
    error_message = "Use 2-10 lowercase letters, numbers or hyphens, starting with a letter."
  }
}
variable "owner" {
  type = string
}
variable "budget_email" {
  type = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.budget_email))
    error_message = "Provide a valid notification email."
  }
}
variable "monthly_budget_usd" {
  type    = number
  default = 30
  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "Budget must be positive."
  }
}
variable "enable_stream" {
  description = "Billable stream is opt-in; disable or destroy after every demo."
  type        = bool
  default     = false
}
variable "producer_principal_arn" {
  description = "Existing local operator IAM role ARN allowed to assume the producer role."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.producer_principal_arn))
    error_message = "Provide an existing IAM role ARN (not an account root or user)."
  }
}
