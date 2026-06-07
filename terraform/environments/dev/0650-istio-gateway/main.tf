locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0650-istio-gateway"
    ops_owners           = "platform-team"
  }

  # Annotations applied to the auto-provisioned LoadBalancer Service.
  # Istio's Gateway API controller copies spec.infrastructure.annotations from
  # the Gateway resource onto the Service it creates for it.
  #
  # Pattern: TLS termination at the AWS classic LB (HTTPS:443 -> HTTP:80 backend).
  # The Envoy gateway pod always speaks plain HTTP; ACM does TLS work.
  lb_annotations = merge(
    {
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
# istio-ingress namespace — shared by external + internal platform Gateways
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "istio_ingress_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "istio-ingress"
      labels = {
        "istio.io/dataplane-mode" = "none"
      }
    }
  })
}

# -----------------------------------------------------------------------------
# platform-gateway — public-facing Gateway API resource.
#
# The workload Helm chart (`helm/microservice-chart`) emits HTTPRoute resources
# whose `parentRefs` default to (name=platform-gateway, namespace=istio-ingress).
# This Gateway is what they attach to.
#
# When this resource is applied, Istio's Gateway API deployment controller
# (registered via the `istio` GatewayClass by istiod) auto-provisions:
#   - a Deployment named `platform-gateway-istio` running Envoy (proxyv2)
#   - a LoadBalancer Service of the same name
#   - an HPA (default 1-5 replicas; tune via spec.infrastructure or a separate HPA)
#
# Annotations from spec.infrastructure.annotations are copied onto that Service,
# which is how we wire ACM TLS termination at the AWS classic LB.
#
# Listener model (TLS-at-LB pattern):
#   - HTTP listener on port 80, accepts HTTPRoutes from any namespace.
#     The AWS LB sends both HTTP:80 and HTTPS:443 traffic to the backend on
#     port 80 (plain HTTP) when the ACM annotations above are present.
#     The Envoy pod itself never sees TLS.
#
#   - There is intentionally NO HTTPS listener on the Gateway side. TLS is
#     terminated at the LB. To run TLS-at-Envoy instead (mTLS, SNI fan-out,
#     cert-manager-issued certs), define a second listener with protocol HTTPS
#     and a certificateRefs Secret, and remove the ACM annotations.
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "platform_gateway" {
  depends_on = [kubectl_manifest.istio_ingress_namespace]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "platform-gateway"
      namespace = "istio-ingress"
      labels = {
        "app.kubernetes.io/part-of" = "platform"
        "platform.io/scope"         = "external"
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
