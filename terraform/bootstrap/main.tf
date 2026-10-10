# One-time bootstrap: creates the S3 bucket that holds remote state for the main config.
# This stack deliberately uses LOCAL state (chicken-and-egg). Run once, then keep the
# small local state file safe, or migrate it into the bucket afterwards (see README).

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

module "state_bucket" {
  source      = "../modules/state-bucket"
  bucket_name = var.state_bucket_name
  tags        = var.tags
}

variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally-unique bucket name, e.g. acme-tfstate-123456789012."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Purpose   = "terraform-state"
  }
}

output "state_bucket_name" {
  description = "Put this in terraform/backend.hcl."
  value       = module.state_bucket.bucket_name
}
