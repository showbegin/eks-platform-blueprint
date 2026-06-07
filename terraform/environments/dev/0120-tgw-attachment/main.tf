locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0120-tgw-attachment"
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

# Workload account provider
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

# Management account provider — needed for TGW route table updates
# (the TGW lives in the management account)
provider "aws" {
  alias  = "management"
  region = local.aws_region

  default_tags {
    tags = merge({
      Project   = "eks-platform-blueprint"
      ManagedBy = "Terraform"
    }, var.tags)
  }

  dynamic "assume_role" {
    for_each = var.management_role_arn == null ? [] : [1]
    content {
      role_arn = var.management_role_arn
    }
  }
}

# -----------------------------------------------------------------------------
# Remote state references
# -----------------------------------------------------------------------------

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0110-vpc/terraform.tfstate"
    region = local.aws_region
  }
}

data "terraform_remote_state" "tgw" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "management/0110-transit-gateway/terraform.tfstate"
    region = local.aws_region
  }
}

# -----------------------------------------------------------------------------
# TGW VPC Attachment — connects this environment's VPC to the shared TGW
# -----------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  subnet_ids         = data.terraform_remote_state.vpc.outputs.eks_worker_subnets
  transit_gateway_id = data.terraform_remote_state.tgw.outputs.transit_gateway_id
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id

  tags = merge(local.tags, {
    Name = "${local.environment_name}-tgw-attachment"
  })
}

# Associate attachment with TGW route table (management account)
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  provider                       = aws.management
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = data.terraform_remote_state.tgw.outputs.tgw_route_table_id
}

# TGW route pointing to this environment's secondary CIDR
resource "aws_ec2_transit_gateway_route" "to_env" {
  provider                       = aws.management
  destination_cidr_block         = var.env_secondary_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = data.terraform_remote_state.tgw.outputs.tgw_route_table_id
}

# VPC routes to peer environments via TGW
data "aws_route_tables" "env" {
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
}

resource "aws_route" "to_peers" {
  for_each = toset(var.peer_cidr_blocks)

  route_table_id         = data.aws_route_tables.env.ids[0]
  destination_cidr_block = each.value
  transit_gateway_id     = data.terraform_remote_state.tgw.outputs.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
