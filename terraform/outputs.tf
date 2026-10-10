output "ecr_repository_url" {
  description = "Registry URL to push images to and reference in k8s manifests."
  value       = module.ecr.repository_url
}

output "ci_role_arn" {
  description = "Set as the AWS_CI_ROLE_ARN repository variable in GitHub."
  value       = module.ci_role.role_arn
}
