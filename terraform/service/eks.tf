# EKS Auto Mode: AWS manages nodes (Karpenter-based), core add-ons, the load balancer
# controller and Pod Identity. No node groups or controller Helm charts to operate.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = local.shared.vpc_id
  subnet_ids = local.shared.private_subnet_ids

  # Public API endpoint restricted to known CIDRs; nodes talk to it privately.

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  # the NetworkPolicy in k8s/app can allow DNS to 172.20.0.10 (CoreDNS).
  service_ipv4_cidr = "172.20.0.0/16"

  deletion_protection = true

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  # Whoever runs terraform apply, plus any extra admins, get cluster-admin via EKS access entries.
  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for arn in var.admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}
