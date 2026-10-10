output "repository_url" {
  description = "Repository URL (registry/name) used in docker push and k8s manifests."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "Repository ARN (used to scope IAM permissions)."
  value       = aws_ecr_repository.this.arn
}
