variable "role_name" {
  description = "Name of the IAM role assumed by CI."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the role, as owner/name."
  type        = string
}

variable "allowed_refs" {
  description = "Git refs allowed to assume the role. Default: main only (PRs get no cloud access)."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "ecr_repository_arn" {
  description = "ARN of the single ECR repository CI may push to."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider. Null creates one."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
