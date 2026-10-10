output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "acm_certificate_arn" {
  description = "Paste into k8s/platform/platform.yaml (certificateARNs)."
  value       = aws_acm_certificate_validation.app.certificate_arn
}

output "secret_name" {
  description = "Secrets Manager secret to populate; referenced by k8s/app/externalsecret.yaml."
  value       = aws_secretsmanager_secret.patient_notes_api.name
}

output "external_secrets_role_arn" {
  description = "Role assumed by the External Secrets controller via Pod Identity."
  value       = aws_iam_role.external_secrets.arn
}
