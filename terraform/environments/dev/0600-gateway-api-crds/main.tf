locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0600-gateway-api-crds"
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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
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
# Gateway API CRDs (kubernetes-sigs/gateway-api, standard install channel)
#
# WHY THIS IS A SEPARATE MODULE:
#   The platform's istio-gateway / istio-gateway-internal modules create
#   Gateway API resources (`Gateway` kind), and the workload Helm chart
#   (`helm/microservice-chart`) emits `HTTPRoute` resources. Both kinds belong
#   to the `gateway.networking.k8s.io` API group, which is NOT installed by
#   default on EKS. Without these CRDs:
#     - terraform plan in 0650/0660 fails ("no matches for kind Gateway")
#     - any helm template that emits HTTPRoute fails on apply
#
#   These CRDs are cluster-scoped and version-coupled to Istio's controller
#   support matrix. Pin via var.gateway_api_version, bump deliberately.
#
# WHY kubectl_manifest, NOT kubernetes_manifest:
#   The hashicorp/kubernetes provider's kubernetes_manifest validates against
#   the cluster's API at PLAN time. For meta-resources (CRDs that define new
#   kinds), this creates a chicken-and-egg loop on a fresh cluster (Finding 8).
#   gavinbunney/kubectl defers validation to apply time, which is correct for
#   bootstrap / CRD-installation flows.
# -----------------------------------------------------------------------------

data "http" "gateway_api_standard_install" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"

  request_headers = {
    Accept = "text/yaml"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Failed to fetch Gateway API standard-install manifest for version ${var.gateway_api_version}: HTTP ${self.status_code}"
    }
  }
}

# Split the multi-document manifest into individual documents for kubectl_manifest.
# kubectl provider requires one document per resource for clean tracking.
data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_standard_install.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = data.kubectl_file_documents.gateway_api_crds.manifests

  yaml_body = each.value

  # CRDs can take a few seconds for the API server to register them after apply.
  # The default wait_for_rollout=true is fine for CRDs (waits for Established).
}
