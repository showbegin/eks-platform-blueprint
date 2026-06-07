locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  # Strip scheme for the OIDC provider URL + condition-key prefix.
  oidc_host = replace(var.gitlab_server_url, "https://", "")

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0240-cicd-oidc"
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0210-eks/terraform.tfstate"
    region = local.aws_region
  }
}

data "terraform_remote_state" "ecr" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0330-ecr/terraform.tfstate"
    region = local.aws_region
  }
}

# -----------------------------------------------------------------------------
# GitLab OIDC identity provider
#
# One per account. Lets GitLab CI jobs exchange a signed id_token for AWS creds
# via sts:AssumeRoleWithWebIdentity — no AWS access keys stored in GitLab.
# -----------------------------------------------------------------------------

data "tls_certificate" "gitlab" {
  url = "${var.gitlab_server_url}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = var.gitlab_server_url
  client_id_list  = [var.gitlab_audience]
  thumbprint_list = [data.tls_certificate.gitlab.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, { Name = "${local.oidc_host}-oidc" })
}

# -----------------------------------------------------------------------------
# Deploy role — assumed by this project's pipelines on the allowed branches.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [var.gitlab_audience]
    }

    # Restrict to this project + the allowed branches only.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = [for b in var.allowed_branches : "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${b}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = var.role_name
  description        = "GitLab CI deploy role for ${var.gitlab_project_path} (OIDC)"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = local.tags
}

# Permissions: ECR push + EKS describe (for update-kubeconfig). Cluster RBAC is
# granted separately via the EKS access entry below.
data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = values(data.terraform_remote_state.ecr.outputs.repository_arns)
  }

  statement {
    sid       = "EKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${local.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${data.terraform_remote_state.eks.outputs.cluster_name}"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.permissions.json
}

# -----------------------------------------------------------------------------
# EKS access entry — grant the deploy role Kubernetes API access so `helm` works.
# Uses access entries (no aws-auth ConfigMap editing).
# -----------------------------------------------------------------------------

resource "aws_eks_access_entry" "deploy" {
  cluster_name  = data.terraform_remote_state.eks.outputs.cluster_name
  principal_arn = aws_iam_role.deploy.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "deploy" {
  cluster_name  = data.terraform_remote_state.eks.outputs.cluster_name
  principal_arn = aws_iam_role.deploy.arn
  policy_arn    = var.eks_access_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.deploy]
}

# -----------------------------------------------------------------------------
# AI review role — assumed by this project's MR pipelines. Scoped to ONLY
# bedrock:InvokeModel (no ECR/EKS/deploy access). Trust allows any ref in this
# project (MR pipelines run on the source branch), but nothing else.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ai_review_trust" {
  count = var.ai_review_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [var.gitlab_audience]
    }

    # Any pipeline (incl. merge_request_event) in THIS project only.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = ["project_path:${var.gitlab_project_path}:*"]
    }
  }
}

resource "aws_iam_role" "ai_review" {
  count              = var.ai_review_enabled ? 1 : 0
  name               = var.ai_review_role_name
  description        = "GitLab CI AI MR-review role for ${var.gitlab_project_path} (OIDC, Bedrock-only)"
  assume_role_policy = data.aws_iam_policy_document.ai_review_trust[0].json
  tags               = local.tags
}

data "aws_iam_policy_document" "ai_review_permissions" {
  count = var.ai_review_enabled ? 1 : 0

  statement {
    sid       = "BedrockInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = var.bedrock_model_arn_patterns
  }
}

resource "aws_iam_role_policy" "ai_review" {
  count  = var.ai_review_enabled ? 1 : 0
  name   = "${var.ai_review_role_name}-permissions"
  role   = aws_iam_role.ai_review[0].id
  policy = data.aws_iam_policy_document.ai_review_permissions[0].json
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC provider + Bedrock-only AI-review role (optional).
# -----------------------------------------------------------------------------

data "tls_certificate" "github" {
  count = var.github_ai_review_enabled ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.github_ai_review_enabled ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = [var.github_oidc_audience]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, { Name = "github-actions-oidc" })
}

data "aws_iam_policy_document" "github_ai_review_trust" {
  count = var.github_ai_review_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = [var.github_oidc_audience]
    }

    # Any pipeline/PR in THIS repo only.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

data "aws_iam_policy_document" "github_bedrock" {
  count = var.github_ai_review_enabled ? 1 : 0

  statement {
    sid       = "BedrockInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = var.bedrock_model_arn_patterns
  }
}

resource "aws_iam_role" "github_ai_review" {
  count              = var.github_ai_review_enabled ? 1 : 0
  name               = var.github_ai_review_role_name
  description        = "GitHub Actions AI PR-review role for ${var.github_repo} (OIDC, Bedrock-only)"
  assume_role_policy = data.aws_iam_policy_document.github_ai_review_trust[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "github_ai_review" {
  count  = var.github_ai_review_enabled ? 1 : 0
  name   = "${var.github_ai_review_role_name}-permissions"
  role   = aws_iam_role.github_ai_review[0].id
  policy = data.aws_iam_policy_document.github_bedrock[0].json
}
