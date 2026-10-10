provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}

# Network, registry and CI role come from the shared stack.
data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "shared/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  shared        = data.terraform_remote_state.shared.outputs
  cluster_name  = "platform-${var.environment}"
  secret_prefix = "${var.service_name}/${var.environment}"

  tags = {
    Service     = var.service_name
    Environment = var.environment
    Stack       = "service"
    ManagedBy   = "terraform"
  }
}
