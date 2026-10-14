provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# This Terraform code is used to retrieve the AWS Availability Zones (AZs) that are available in your AWS region,
# while filtering out zones that require an explicit opt-in to use.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project   = var.project
    Stack     = "shared"
    ManagedBy = "terraform"
  }
}

# Remote state bucket (used by both the shared and service stacks).
module "state_bucket" {
  source = "../modules/state-bucket"

  bucket_name = var.state_bucket_name
}

# Network: 3 AZs, private subnets for workloads, public subnets for load balancers.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.project
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway # false means per-AZ gateways; true means one shared gateway.

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 30

  # Tags EKS Auto Mode uses to place internet-facing / internal load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "ecr" {
  source = "../modules/ecr"

  name             = var.service_name
  keep_last_images = var.ecr_keep_last_images
}

# CI authenticates to AWS with GitHub OIDC (no stored keys) and may only push to this one repository.
module "ci_role" {
  source = "../modules/ci-iam-role"

  role_name          = "${var.service_name}-ci"
  github_repository  = var.github_repository
  ecr_repository_arn = module.ecr.repository_arn
}
