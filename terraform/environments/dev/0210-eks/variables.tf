variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  default     = "dev"
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume for cross-account access. Set to null for single-account deployments."
  type        = string
  default     = null
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform remote state lookups"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API endpoint (disable in prod for security)"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "addon_versions" {
  description = "EKS managed addon versions (pin for reproducibility). Lookup current values via: aws eks describe-addon-versions --kubernetes-version <ver> --addon-name <name>"
  type        = map(string)
  default = {
    "ebs-csi"    = "v1.60.1-eksbuild.1"
    "kube-proxy" = "v1.35.3-eksbuild.11"
    "coredns"    = "v1.14.3-eksbuild.2"
    "vpc-cni"    = "v1.22.1-eksbuild.2"
  }
}

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions"
  type        = any
  default = {
    default = {
      ami_type             = "BOTTLEROCKET_ARM_64"
      platform             = "bottlerocket"
      force_update_version = true

      desired_size   = 2
      max_size       = 3
      min_size       = 1
      instance_types = ["m6g.xlarge"]

      block_device_mappings = {
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size           = 200
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }

      k8s_labels = {}
    }
  }
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
