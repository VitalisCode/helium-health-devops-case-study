
resource "aws_secretsmanager_secret" "patient_notes_api" {
  name                    = "${local.secret_prefix}/app"
  description             = "Runtime secrets for Patient Notes API (${var.environment}). Value managed outside Terraform."
  recovery_window_in_days = 30
}


# Role assumed by the External Secrets controller through EKS Pod Identity.
data "aws_iam_policy_document" "pods_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.eks.cluster_arn]
    }
  }
}


resource "aws_iam_role" "external_secrets" {
  name               = "${local.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pods_trust.json
}


# Least privilege: read-only on this service's secrets for this environment.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secret_prefix}/*",
    ]
  }
}


resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-service-secrets"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}


# Binds the role to the controller's service account (namespace/name set by its Helm chart).
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}
