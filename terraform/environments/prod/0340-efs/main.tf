locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0340-efs"
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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0210-eks/terraform.tfstate"
    region = local.aws_region
  }
}

# -----------------------------------------------------------------------------
# EFS file system — encrypted, lifecycle to IA after configurable days
# -----------------------------------------------------------------------------

resource "aws_efs_file_system" "this" {
  creation_token = "${local.environment_name}-${var.efs_name}"
  encrypted      = true

  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }

  tags = merge(local.tags, {
    Name = "${local.environment_name}-${var.efs_name}"
  })
}

# -----------------------------------------------------------------------------
# Security group — NFS from EKS nodes
# -----------------------------------------------------------------------------

resource "aws_security_group" "efs" {
  name_prefix = "efs-${local.environment_name}-${var.efs_name}-"
  description = "EFS mount target security group — NFS from EKS nodes"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description     = "NFS from EKS node security group"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.eks.outputs.node_security_group_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "efs-${local.environment_name}-${var.efs_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Mount targets — one per EKS worker subnet
# -----------------------------------------------------------------------------

resource "aws_efs_mount_target" "this" {
  count = length(data.terraform_remote_state.vpc.outputs.eks_worker_subnets)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = data.terraform_remote_state.vpc.outputs.eks_worker_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}
