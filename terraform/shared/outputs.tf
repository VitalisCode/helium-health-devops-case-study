output "state_bucket_name" {
  description = "State bucket name (used in backend.hcl and as the service stack's state_bucket_name)."
  value       = module.state_bucket.bucket_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes and pods)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (internet-facing load balancers)."
  value       = module.vpc.public_subnets
}

output "ecr_repository_url" {
  description = "ECR repository URL images are pushed to."
  value       = module.ecr.repository_url
}

output "ci_role_arn" {
  description = "Set as the AWS_CI_ROLE_ARN repository variable in GitHub."
  value       = module.ci_role.role_arn
}
