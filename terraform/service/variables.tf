variable "aws_region" {
  description = "AWS region; must match the shared stack."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "State bucket created by the shared stack (also used to read its outputs)."
  type        = string
}

variable "service_name" {
  description = "Service name; prefixes the Secrets Manager path."
  type        = string
  default     = "patient-notes-api"
}

variable "environment" {
  description = "Environment name (cluster name suffix, secret path, tags)."
  type        = string
  default     = "production"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Pick one currently in EKS standard support, e.g. \"1.34\"."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.34\"."
  }
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint (office/VPN ranges). No default on purpose."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "Extra IAM role/user ARNs granted cluster-admin (the identity running apply is always admin)."
  type        = list(string)
  default     = []
}

variable "domain_name" {
  description = "Public hostname of the API, e.g. notes-api.example.com. Must be in the Route 53 zone below."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID used to validate the ACM certificate."
  type        = string
}
