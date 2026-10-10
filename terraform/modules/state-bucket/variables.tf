variable "bucket_name" {
  description = "Globally-unique name of the S3 bucket that stores Terraform state."
  type        = string
}

variable "kms_key_arn" {
  description = "Optional CMK for SSE-KMS. Null uses S3-managed keys (SSE-S3)."
  type        = string
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Days to keep old state versions (for rollback) before expiring them."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
