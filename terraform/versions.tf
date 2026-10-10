terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Remote state in S3 with native lockfile locking (Terraform >= 1.10, no DynamoDB needed).
  # Bucket/region are NOT hardcoded: pass them at init time so the repo stays portable:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "patient-notes-api/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
