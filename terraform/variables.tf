variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-1"
}

variable "service_name" {
  description = "Service name; used for the ECR repository and role names."
  type        = string
  default     = "patient-notes-api"
}

variable "environment" {
  description = "Environment label applied as a tag."
  type        = string
  default     = "staging"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose workflows may assume the CI role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "ci_allowed_refs" {
  description = "Git refs allowed to assume the CI role."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN. Leave null to create it (one per AWS account)."
  type        = string
  default     = null
}

variable "ecr_keep_last_images" {
  description = "How many images the ECR lifecycle policy retains."
  type        = number
  default     = 30
}

variable "extra_tags" {
  description = "Additional tags merged into the default tags."
  type        = map(string)
  default     = {}
}
