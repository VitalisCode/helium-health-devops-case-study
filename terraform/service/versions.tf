terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bucket/region are passed at init time: terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "service/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
