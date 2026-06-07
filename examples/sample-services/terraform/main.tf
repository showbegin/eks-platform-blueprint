locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  queue_key   = "sample-events"
  queue_name  = "${local.environment_name}-${local.queue_key}"
  bucket_name = "${local.environment_name}-${var.bucket_suffix}"
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
      Demo      = "sample-services"
    }, var.tags)
  }

  dynamic "assume_role" {
    for_each = var.assume_role_arn == null ? [] : [1]
    content {
      role_arn = var.assume_role_arn
    }
  }
}

# Look up cluster OIDC provider for IRSA trust policies
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0210-eks/terraform.tfstate"
    region = local.aws_region
  }
}

# Look up SQS queue created by the messaging module (0410)
data "terraform_remote_state" "messaging" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0410-messaging/terraform.tfstate"
    region = local.aws_region
  }
}
