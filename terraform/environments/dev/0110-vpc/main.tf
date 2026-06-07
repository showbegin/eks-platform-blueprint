locals {
  aws_region       = var.aws_region
  environment_name = var.environment
  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0110-vpc"
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

  backend "s3" {
    # Values injected via -backend-config or backend.hcl per environment.
    # Example:
    #   bucket         = "platform-terraform-state"
    #   key            = "dev/0110-vpc/terraform.tfstate"
    #   region         = "eu-central-1"
    #   dynamodb_table = "platform-terraform-locks"
    #   encrypt        = true
  }
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

# -----------------------------------------------------------------------------
# VPC — using the community module (terraform-aws-modules/vpc/aws)
#
# Pattern: primary CIDR for infrastructure subnets (private, public),
# secondary CIDR for EKS worker nodes (keeps pod networking isolated from
# infrastructure addressing).
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0"

  name = local.environment_name
  cidr = var.vpc_cidr

  secondary_cidr_blocks = var.secondary_cidr_blocks

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # EKS worker node subnets — using the elasticache_subnets slot from the
  # community module as a convenient way to get a third subnet tier without
  # forking the module. These are NOT actually for ElastiCache.
  elasticache_subnets = var.eks_worker_subnets

  # NAT Gateway — one per AZ for HA in production, single for dev/stage cost savings
  enable_nat_gateway     = true
  one_nat_gateway_per_az = var.one_nat_gateway_per_az
  single_nat_gateway     = var.single_nat_gateway

  # VPN Gateway — enable if cross-VPC or on-prem connectivity needed
  enable_vpn_gateway = var.enable_vpn_gateway

  tags = local.tags
}
