variable "name" {
  description = "Repository name."
  type        = string
}

variable "keep_last_images" {
  description = "Number of most recent images to retain."
  type        = number
  default     = 30
}

variable "untagged_expire_days" {
  description = "Days before untagged images are expired."
  type        = number
  default     = 7
}

variable "kms_key_arn" {
  description = "Optional CMK for repository encryption. Null uses AES256."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
