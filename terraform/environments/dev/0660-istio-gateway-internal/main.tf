locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0660-istio-gateway-internal"
    ops_owners           = "platform-team"
  }

  # Annotations for the auto-provisioned LoadBalancer Service.
  # Internal LB (no public IP) for cross-account / VPC-peered traffic via TGW.
  # TLS termination at the LB pattern, identical to the external Gateway (0650).
  lb_annotations = merge(
    {
      "service.beta.kubernetes.io/aws-load-balancer-internal"                          = "true"
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "classic"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
      "service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout"           = "3600"
    },
    var.acm_certificate_arn != null ? {
      "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"         = var.acm_certificate_arn
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "http"
      "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "https"
    } : {}
  )
}

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.45"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0210-eks/terraform.tfstate"
    region = local.aws_region
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

# -----------------------------------------------------------------------------
# platform-gateway-internal — internal Gateway API resource for cross-account /
# VPC-peered traffic (e.g., requests from peered VPCs via Transit Gateway).
#
# Same architecture as 0650's `platform-gateway`, with two differences:
#   1. The auto-provisioned LB Service carries `aws-load-balancer-internal: "true"`,
#      so the LB is provisioned without a public IP.
#   2. Workloads attach via parentRefs.name=platform-gateway-internal in their
#      HTTPRoute / GRPCRoute resources.
#
# The `istio-ingress` namespace is created by 0650 and reused here; this module
# adds a depends_on through the remote-state read implicitly (apply 0650 first).
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "platform_gateway_internal" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "platform-gateway-internal"
      namespace = "istio-ingress"
      labels = {
        "app.kubernetes.io/part-of" = "platform"
        "platform.io/scope"         = "internal"
      }
    }
    spec = {
      gatewayClassName = "istio"
      listeners = [
        {
          name     = "http"
          port     = 80
          protocol = "HTTP"
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
      ]
      infrastructure = {
        annotations = local.lb_annotations
      }
    }
  })
}
