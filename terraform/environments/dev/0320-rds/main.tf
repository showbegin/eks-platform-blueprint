locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0320-rds"
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

data "terraform_remote_state" "bastion" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0230-bastion/terraform.tfstate"
    region = local.aws_region
  }
}

# Database password from SSM Parameter Store (encrypted at rest, auditable)
data "aws_ssm_parameter" "db_password" {
  name = var.db_password_ssm_path
}

# Subnet metadata for CIDR-based ingress rules
data "aws_subnet" "private" {
  count = length(data.terraform_remote_state.vpc.outputs.private_subnets)
  id    = data.terraform_remote_state.vpc.outputs.private_subnets[count.index]
}

data "aws_subnet" "eks_workers" {
  count = length(data.terraform_remote_state.vpc.outputs.eks_worker_subnets)
  id    = data.terraform_remote_state.vpc.outputs.eks_worker_subnets[count.index]
}

# -----------------------------------------------------------------------------
# Subnet group — RDS lives in private subnets only
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "rds-${local.environment_name}"
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets
  tags       = local.tags
}

# -----------------------------------------------------------------------------
# Security group — allow PostgreSQL from private subnets, EKS workers, bastion
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "rds-${local.environment_name}"
  description = "RDS access from private subnets, EKS workers, and bastion"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "PostgreSQL from private + EKS worker CIDRs"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat(
      [for s in data.aws_subnet.private : s.cidr_block],
      [for s in data.aws_subnet.eks_workers : s.cidr_block]
    )
  }

  ingress {
    description     = "PostgreSQL from bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.bastion.outputs.bastion_security_group_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# RDS instance — PostgreSQL
# -----------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "rds-${local.environment_name}"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = data.aws_ssm_parameter.db_password.value
  port     = 5432

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "rds-${local.environment_name}-final"
  deletion_protection       = var.deletion_protection

  tags = local.tags
}
