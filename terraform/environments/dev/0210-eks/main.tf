locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0210-eks"
    ops_owners           = "platform-team"
  }
}

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.45"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = local.aws_region

  default_tags {
    tags = merge({
      Project   = "eks-platform-blueprint"
      ManagedBy = "Terraform"
    }, var.tags)
  }

  dynamic "assume_role" {
    for_each = var.assume_role_arn == null ? [] : [1]
    content {
      role_arn = var.assume_role_arn
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Resolves the actual role ARN when the current credentials are an STS
# assumed-role session. Used to grant the role that ran terraform apply
# admin access to the cluster, even in single-account mode where
# var.assume_role_arn is null.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# -----------------------------------------------------------------------------
# Remote state — VPC
# -----------------------------------------------------------------------------

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0110-vpc/terraform.tfstate"
    region = local.aws_region
  }
}

# -----------------------------------------------------------------------------
# KMS — EKS secret encryption + CloudWatch logs
# -----------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  description         = "${local.environment_name} EKS secret encryption key"
  enable_key_rotation = true
  tags                = local.tags
}

data "aws_iam_policy_document" "cloudwatch_kms" {
  statement {
    sid    = "EnableRootUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.environment_name}/cluster"]
    }
  }
}

resource "aws_kms_key" "cloudwatch" {
  description         = "${local.environment_name} EKS CloudWatch logs encryption key"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.cloudwatch_kms.json
  tags                = local.tags
}

# -----------------------------------------------------------------------------
# EBS CSI Driver IRSA role
# -----------------------------------------------------------------------------

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.3"

  name                  = "${local.environment_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.3.1"

  tags = local.tags

  name               = local.environment_name
  kubernetes_version = var.kubernetes_version
  enable_irsa        = true

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.eks_worker_subnets

  # API access — public for dev/stage, private-only for prod
  endpoint_private_access      = var.cluster_endpoint_private_access
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # EKS managed addons — pinned versions for reproducibility
  addons = {
    aws-ebs-csi-driver = {
      addon_version               = var.addon_versions["ebs-csi"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      service_account_role_arn    = module.ebs_csi_irsa_role.arn
    }
    kube-proxy = {
      addon_version               = var.addon_versions["kube-proxy"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    coredns = {
      addon_version               = var.addon_versions["coredns"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      # Must be installed before node group is provisioned, otherwise
      # nodes never become Ready (no CNI -> aws-node DaemonSet can't run
      # -> kubelet reports NetworkPluginNotReady -> node group blocks).
      before_compute              = true
      addon_version               = var.addon_versions["vpc-cni"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  cloudwatch_log_group_kms_key_id        = aws_kms_key.cloudwatch.arn
  cloudwatch_log_group_retention_in_days = var.cloudwatch_log_group_retention_in_days
  enabled_log_types                      = var.cluster_enabled_log_types

  # Access management — API mode (recommended for EKS 1.30+)
  authentication_mode = "API_AND_CONFIG_MAP"
  access_entries = {
    platform_admin = {
      kubernetes_groups = []
      # Fall back to the role that ran `terraform apply` if no cross-account
      # role is configured. This makes single-account mode (ADR-009) work
      # without manual access-entry setup.
      principal_arn = coalesce(var.assume_role_arn, data.aws_iam_session_context.current.issuer_arn)

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            namespaces = []
            type       = "cluster"
          }
        }
      }
    }
  }

  # Node groups
  eks_managed_node_groups = var.eks_managed_node_groups

  # Security group rules — allow webhook validation from API to nodes
  node_security_group_additional_rules = {
    allow_internal_ranges = {
      description = "Allow inbound from internal RFC1918 + shared-services ranges"
      protocol    = "all"
      from_port   = 0
      to_port     = 65535
      type        = "ingress"
      cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"]
    }
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    inbound_from_eks_api = {
      description                   = "Inbound from EKS API to nodes (webhook validation)"
      protocol                      = "tcp"
      from_port                     = 0
      to_port                       = 65535
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}

# Data sources for kubernetes provider (must reference the created cluster)
data "aws_eks_cluster" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Default StorageClass — gp3 backed by the EBS CSI driver
#
# WHY THIS IS HERE:
#   EKS 1.35 ships a `gp2` StorageClass annotated as default, but its
#   provisioner is `kubernetes.io/aws-ebs` — the in-tree provisioner that was
#   deprecated in K8s 1.27 and removed in K8s 1.31. The class exists but
#   cannot actually provision volumes. Without a working default StorageClass,
#   any PVC-using workload (kube-prometheus-stack, Grafana, user services)
#   hangs Pending forever with no clear error.
#
#   This module installs the aws-ebs-csi-driver addon (provisioner
#   `ebs.csi.aws.com`), so the StorageClass that consumes it belongs here too.
#
# WHAT THIS DOES:
#   1. Creates a `gp3` StorageClass marked default, encrypted, WaitForFirstConsumer.
#   2. Clears the legacy `gp2` StorageClass's is-default-class annotation so
#      we don't end up with two defaults (Kubernetes treats that as undefined
#      behaviour and may pick either).
#
#   The depends_on chain ensures the CSI driver addon is ACTIVE before the
#   StorageClass references it.
# -----------------------------------------------------------------------------

resource "kubernetes_storage_class_v1" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [module.eks]
}

# Clear the legacy gp2 StorageClass's default annotation. We use
# kubernetes_annotations (force=true) rather than recreating the class, since
# the legacy class is created by EKS itself outside Terraform's lifecycle.
resource "kubernetes_annotations" "gp2_clear_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"

  metadata {
    name = "gp2"
  }

  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  force = true

  depends_on = [module.eks]
}
