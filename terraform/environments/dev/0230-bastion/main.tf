locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0230-bastion"
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
# IAM role + instance profile — bastion needs eks:DescribeCluster to fetch
# kubeconfig. Cluster-side access (RBAC) requires adding this role's ARN to
# the EKS module's `access_entries` map (see outputs.tf for the role ARN).
# -----------------------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  name_prefix = "${local.environment_name}-bastion-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# Minimal EKS read access — sufficient to run `aws eks update-kubeconfig`.
# Cluster-internal authorization is handled by access entries (see EKS module).
resource "aws_iam_role_policy" "bastion_eks_describe" {
  name = "eks-describe"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:AccessKubernetesApi"
      ]
      Resource = "*"
    }]
  })
}

# SSM Session Manager — preferred over SSH for a real bastion (no SG ingress
# required, full audit trail). SSH stays available as a fallback.
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name_prefix = "${local.environment_name}-bastion-"
  role        = aws_iam_role.bastion.name
  tags        = local.tags
}

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------

resource "aws_key_pair" "bastion" {
  key_name   = "${local.environment_name}-bastion-key"
  public_key = var.ssh_public_key
  tags       = local.tags
}

# -----------------------------------------------------------------------------
# Security Group — SSH inbound, all outbound
# -----------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name_prefix = "${local.environment_name}-bastion-"
  description = "Bastion host — SSH inbound from allowed CIDRs"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.environment_name}-bastion-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# AMI — latest Amazon Linux 2023
# -----------------------------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.bastion.key_name

  iam_instance_profile = aws_iam_instance_profile.bastion.name

  subnet_id                   = data.terraform_remote_state.vpc.outputs.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only — security best practice
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # PostgreSQL client for RDS access
    dnf install -y postgresql15 jq

    # kubectl — official binary (not in AL2023 dnf repos)
    KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$${KUBE_VERSION}/bin/linux/amd64/kubectl"
    chmod 0755 /usr/local/bin/kubectl

    # helm — official install script
    curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # AWS CLI v2 is preinstalled on AL2023; verify
    aws --version

    # Welcome banner with kubeconfig hint
    cat > /etc/motd <<MOTD
    Bastion: ${local.environment_name}
    To configure kubectl:
      aws eks update-kubeconfig --region ${local.aws_region} --name ${local.environment_name}
    Cluster access requires an EKS access entry for this instance's role:
      ${aws_iam_role.bastion.name}
    MOTD
  EOF

  tags = merge(local.tags, {
    Name = "${local.environment_name}-bastion"
  })
}
