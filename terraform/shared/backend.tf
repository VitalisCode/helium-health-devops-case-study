

#   terraform init -backend-config=backend.tf.hcl
terraform {
  backend "s3" {
    key          = "shared/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
