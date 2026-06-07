locals {
  bucket_name = "${var.project_name}-terraform-state"
  table_name  = "${var.project_name}-terraform-locks"

  common_tags = merge(var.tags, {
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/backend/0010-state-backend"
  })
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge({
      Project   = "eks-platform-blueprint"
      ManagedBy = "Terraform"
    }, var.tags)
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket — stores all Terraform state files
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name
  tags   = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# -----------------------------------------------------------------------------
# DynamoDB Table — state locking
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}
