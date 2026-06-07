locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0130-route53-hostedzone"
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

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0110-vpc/terraform.tfstate"
    region = local.aws_region
  }
}

# -----------------------------------------------------------------------------
# Route53 Public Hosted Zone — external DNS records (cert-manager, external-dns)
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "public" {
  name    = var.domain_name
  comment = "${local.environment_name} public hosted zone"
  tags    = local.tags
}

# -----------------------------------------------------------------------------
# Route53 Private Hosted Zone — split-horizon DNS for internal service discovery
# Associates with the environment VPC so pods can resolve internal names.
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "private" {
  name    = var.domain_name
  comment = "${local.environment_name} private hosted zone (split-horizon)"

  vpc {
    vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
    vpc_region = local.aws_region
  }

  tags = local.tags
}
