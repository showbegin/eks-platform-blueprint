locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0330-aurora"
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

data "aws_subnet" "private" {
  count = length(data.terraform_remote_state.vpc.outputs.private_subnets)
  id    = data.terraform_remote_state.vpc.outputs.private_subnets[count.index]
}

data "aws_subnet" "eks_workers" {
  count = length(data.terraform_remote_state.vpc.outputs.eks_worker_subnets)
  id    = data.terraform_remote_state.vpc.outputs.eks_worker_subnets[count.index]
}

# Master password from SSM (encrypted)
data "aws_ssm_parameter" "master_password" {
  name            = var.master_password_ssm_path
  with_decryption = true
}

# Per-user app passwords from SSM (encrypted) — one entry per user in var.app_users
data "aws_ssm_parameter" "app_password" {
  for_each        = toset(var.app_users)
  name            = "${var.app_password_ssm_prefix}/${each.key}"
  with_decryption = true
}

# -----------------------------------------------------------------------------
# Subnet group (uses 3 private subnets across AZs for Aurora)
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-${local.environment_name}"
  subnet_ids = slice(data.terraform_remote_state.vpc.outputs.private_subnets, 0, 3)
  tags       = local.tags
}

# -----------------------------------------------------------------------------
# Security group — allow PostgreSQL from private + EKS worker CIDRs
# -----------------------------------------------------------------------------

resource "aws_security_group" "aurora" {
  name_prefix = "aurora-${local.environment_name}-"
  description = "Aurora cluster security group"
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

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "aurora-${local.environment_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Aurora PostgreSQL cluster + 3 instances
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "aurora" {
  cluster_identifier   = "aurora-${local.environment_name}"
  engine               = "aurora-postgresql"
  engine_version       = var.engine_version
  database_name        = var.db_name
  master_username      = var.master_username
  master_password      = data.aws_ssm_parameter.master_password.value
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  vpc_security_group_ids = [aws_security_group.aurora.id]

  # Production-grade backup posture
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:30-sun:05:30"

  enabled_cloudwatch_logs_exports = ["postgresql"]
  storage_encrypted               = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "aurora-${local.environment_name}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  copy_tags_to_snapshot     = true

  tags = local.tags

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_rds_cluster_instance" "aurora" {
  count = var.instance_count

  identifier         = "aurora-${local.environment_name}-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  publicly_accessible = false

  tags = merge(local.tags, {
    Name = "aurora-${local.environment_name}-${count.index}"
  })
}

# -----------------------------------------------------------------------------
# RDS Proxy — connection pooling + per-user secrets-managed auth
#
# Pattern: each app user gets its own Secrets Manager secret. RDS Proxy
# authenticates via these secrets, applications connect to the proxy.
# -----------------------------------------------------------------------------

# Master credentials secret
resource "aws_secretsmanager_secret" "master" {
  name = "aurora-${local.environment_name}-master"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = var.master_username
    password = data.aws_ssm_parameter.master_password.value
  })
}

# App user credentials secrets (one per user)
resource "aws_secretsmanager_secret" "app_user" {
  for_each = toset(var.app_users)
  name     = "aurora-${local.environment_name}-${each.key}"
  tags     = local.tags
}

resource "aws_secretsmanager_secret_version" "app_user" {
  for_each  = toset(var.app_users)
  secret_id = aws_secretsmanager_secret.app_user[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = data.aws_ssm_parameter.app_password[each.key].value
  })
}

# IAM role for RDS Proxy to read secrets
data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_proxy" {
  name               = "rds-proxy-${local.environment_name}"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "rds_proxy" {
  name = "rds-proxy-${local.environment_name}"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = concat(
        [aws_secretsmanager_secret.master.arn],
        [for s in aws_secretsmanager_secret.app_user : s.arn]
      )
    }]
  })
}

# Security group for RDS Proxy
resource "aws_security_group" "rds_proxy" {
  name_prefix = "rds-proxy-${local.environment_name}-"
  description = "RDS Proxy security group"
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

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "rds-proxy-${local.environment_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_proxy" "aurora" {
  name          = "aurora-proxy-${local.environment_name}"
  engine_family = "POSTGRESQL"

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.master.arn
  }

  dynamic "auth" {
    for_each = aws_secretsmanager_secret.app_user
    content {
      auth_scheme = "SECRETS"
      iam_auth    = "DISABLED"
      secret_arn  = auth.value.arn
    }
  }

  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = slice(data.terraform_remote_state.vpc.outputs.private_subnets, 0, 3)
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  require_tls            = true

  tags = local.tags
}

resource "aws_db_proxy_default_target_group" "aurora" {
  db_proxy_name = aws_db_proxy.aurora.name

  connection_pool_config {
    max_connections_percent      = 100
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "aurora" {
  db_proxy_name         = aws_db_proxy.aurora.name
  target_group_name     = aws_db_proxy_default_target_group.aurora.name
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier
}

resource "aws_security_group_rule" "proxy_to_aurora" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds_proxy.id
  security_group_id        = aws_security_group.aurora.id
  description              = "Allow RDS Proxy to reach Aurora cluster"
}
