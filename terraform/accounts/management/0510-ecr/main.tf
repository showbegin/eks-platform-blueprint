locals {
  aws_region = var.aws_region

  tags = {
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/accounts/management/0510-ecr"
    ops_owners           = "platform-team"
    ops_scope            = "management"
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
# ECR Repositories — one per entry in var.repositories
#
# Each repository:
#   - Image scanning on push (Basic, free)
#   - KMS encryption (or AES256 if no key supplied)
#   - Lifecycle policy: keep last N images per service tag prefix,
#     expire untagged after configurable days, catch-all for old images
#   - Cross-account access policy (push for build accounts, pull for env accounts)
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = each.value.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = each.value.kms_key_arn
  }

  tags = merge(local.tags, {
    Name = each.key
  })
}

# -----------------------------------------------------------------------------
# Lifecycle policy
#
# Pattern:
#   1. Expire untagged images after `untagged_expiration_days`
#   2. For each tag prefix (e.g., "dev-", "stage-"), keep the last
#      `images_per_tag_prefix` images
#   3. Catch-all: expire any image older than `catch_all_expiration_days`
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = concat(
      [
        {
          rulePriority = 1
          description  = "Expire untagged images after ${var.untagged_expiration_days} days"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = var.untagged_expiration_days
          }
          action = { type = "expire" }
        }
      ],
      [
        for idx, prefix in each.value.tag_prefixes : {
          rulePriority = 10 + idx
          description  = "Keep last ${var.images_per_tag_prefix} ${prefix} images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = [prefix]
            countType     = "imageCountMoreThan"
            countNumber   = var.images_per_tag_prefix
          }
          action = { type = "expire" }
        }
      ],
      [
        {
          rulePriority = 100
          description  = "Catch-all: expire images older than ${var.catch_all_expiration_days} days"
          selection = {
            tagStatus   = "any"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = var.catch_all_expiration_days
          }
          action = { type = "expire" }
        }
      ]
    )
  })
}

# -----------------------------------------------------------------------------
# Cross-account access policy
# -----------------------------------------------------------------------------

resource "aws_ecr_repository_policy" "this" {
  for_each = {
    for k, v in var.repositories : k => v
    if length(var.push_principals) + length(var.pull_principals) > 0
  }

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = concat(
      length(var.push_principals) == 0 ? [] : [
        {
          Sid    = "AllowPush"
          Effect = "Allow"
          Principal = {
            AWS = var.push_principals
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
          ]
        }
      ],
      length(var.pull_principals) == 0 ? [] : [
        {
          Sid    = "AllowPull"
          Effect = "Allow"
          Principal = {
            AWS = var.pull_principals
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
          ]
        }
      ]
    )
  })
}
