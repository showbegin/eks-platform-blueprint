locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0620-external-dns"
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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
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

data "terraform_remote_state" "route53" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0130-route53-hostedzone/terraform.tfstate"
    region = local.aws_region
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# -----------------------------------------------------------------------------
# IRSA — external-dns needs Route53 read + record set write
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name   = "external-dns-${local.environment_name}"
  policy = data.aws_iam_policy_document.external_dns.json
  tags   = local.tags
}

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.3"

  name            = "external-dns-${local.environment_name}"
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }

  policies = {
    route53 = aws_iam_policy.external_dns.arn
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# external-dns Helm release
# -----------------------------------------------------------------------------

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = var.chart_version
  namespace        = "external-dns"
  create_namespace = true

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      irsa_role_arn = module.external_dns_irsa.arn
      domain_filter = data.terraform_remote_state.route53.outputs.domain_name
      zone_id       = data.terraform_remote_state.route53.outputs.public_zone_id
      txt_owner_id  = local.environment_name
    })
  ]
}
