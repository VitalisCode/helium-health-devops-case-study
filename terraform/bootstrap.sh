#!/usr/bin/env bash
# One-time bootstrap of the shared stack.

# Usage: AWS_REGION=eu-west-1 ./terraform/bootstrap.sh   (needs terraform/shared/terraform.tfvars)
set -euo pipefail

cd "$(dirname "$0")/shared"
[ -f terraform.tfvars ] || { echo "Create terraform.tfvars first with your development values"; exit 1; }

BUCKET="$(awk -F'"' '/^state_bucket_name/ {print $2}' terraform.tfvars)"
REGION="${AWS_REGION:-eu-west-1}"

# Step 1: bucket only, local state (the backend block is parked while we do this).
mv backend.tf backend.tf.off
trap '[ -f backend.tf.off ] && mv backend.tf.off backend.tf' EXIT
terraform init
terraform apply -target=module.state_bucket

# Step 2: restore the backend and move local state into the new bucket.
mv backend.tf.off backend.tf
terraform init -migrate-state -force-copy \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"

echo "Done. Now run: terraform plan && terraform apply (in terraform/shared)"
