output "role_arn" {
  description = "Set this as the AWS_CI_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.ci.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in use."
  value       = local.oidc_provider
}
