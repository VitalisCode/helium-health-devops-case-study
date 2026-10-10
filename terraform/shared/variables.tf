variable "aws_region" {
  description = "AWS region for all shared resources."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Name prefix for shared resources (VPC, tags)."
  type        = string
  default     = "platform"
}

variable "service_name" {
  description = "Service name; used for the ECR repository and CI role names."
  type        = string
  default     = "patient-notes-api"
}

variable "state_bucket_name" {
  description = "Globally-unique name of the S3 bucket holding Terraform state, e.g. acme-tfstate-123456789012."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose main branch may assume the CI role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR. The Kubernetes NetworkPolicy in k8s/app allows ingress from this range, so keep them in sync."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheaper, single-AZ failure point). Default is one per AZ."
  type        = bool
  default     = false
}

variable "ecr_keep_last_images" {
  description = "How many images the ECR lifecycle policy retains."
  type        = number
  default     = 30
}
