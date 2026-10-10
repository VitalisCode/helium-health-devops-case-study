provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

locals {
  tags = merge(
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

module "ecr" {
  source = "./modules/ecr"

  name                 = var.service_name
  keep_last_images     = var.ecr_keep_last_images
  untagged_expire_days = 7
}

module "ci_role" {
  source = "./modules/ci-iam-role"

  role_name          = "${var.service_name}-ci"
  github_repository  = var.github_repository
  allowed_refs       = var.ci_allowed_refs
  ecr_repository_arn = module.ecr.repository_arn
  oidc_provider_arn  = var.github_oidc_provider_arn
}
