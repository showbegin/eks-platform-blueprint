terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.45"
    }
  }

  # This module bootstraps the S3 backend itself — it CANNOT use the S3
  # backend it creates (chicken-and-egg). Uses local state.
  #
  # After first apply, the bucket and lock table exist. All other modules
  # reference them via their backend "s3" {} blocks.
  #
  # If local terraform.tfstate is lost, re-apply: the module is idempotent
  # (resources referenced by name, Terraform detects existing state).
  backend "local" {}
}
