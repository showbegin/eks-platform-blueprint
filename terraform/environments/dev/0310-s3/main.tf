locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0310-s3"
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

# -----------------------------------------------------------------------------
# S3 Buckets — created from var.buckets map
#
# Each bucket gets:
#   - Server-side encryption (SSE-S3 or SSE-KMS, configurable per-bucket)
#   - Public access fully blocked
#   - Versioning (configurable per-bucket)
#   - Optional lifecycle policy (configurable per-bucket)
#
# Bucket name pattern: {project_name}-{environment}-{bucket_key}
# Example: platform-dev-documents
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket = "${var.project_name}-${local.environment_name}-${each.key}"

  tags = merge(local.tags, {
    Name    = "${var.project_name}-${local.environment_name}-${each.key}"
    Purpose = each.value.purpose
  })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = each.value.versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = each.value.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = each.value.kms_key_arn
    }
    bucket_key_enabled = each.value.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for k, v in var.buckets : k => v if v.lifecycle_rules != null }

  bucket = aws_s3_bucket.this[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules
    content {
      id     = rule.value.id
      status = "Enabled"

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition_to_glacier_days != null ? [1] : []
        content {
          days          = rule.value.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }
    }
  }
}
