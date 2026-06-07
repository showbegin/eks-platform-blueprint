variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  default     = "dev"
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume for cross-account access. Set to null for single-account deployments."
  type        = string
  default     = null
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform remote state lookups"
  type        = string
}

variable "gitlab_server_url" {
  description = "GitLab server URL (the OIDC issuer). For GitLab.com use https://gitlab.com."
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_audience" {
  description = "Audience the pipeline requests in its id_token. Must match the job's id_tokens aud (we use $CI_SERVER_URL)."
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_project_path" {
  description = "GitLab project path the deploy role trusts, e.g. 'showbegin/eks-platform-blueprint'. No leading slash."
  type        = string
}

variable "allowed_branches" {
  description = "Branches whose pipelines may assume the deploy role."
  type        = list(string)
  default     = ["dev", "stage", "prod"]
}

variable "role_name" {
  description = "Name of the deploy IAM role (must match DEPLOY_ROLE_NAME in CI, default platform-deploy)."
  type        = string
  default     = "platform-deploy"
}

variable "eks_access_policy_arn" {
  description = "EKS access policy to associate with the deploy role. ClusterAdmin for the demo; scope down for prod."
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

# -----------------------------------------------------------------------------
# AI merge-request review role (optional, Bedrock-only).
# -----------------------------------------------------------------------------

variable "ai_review_enabled" {
  description = "Create the Bedrock-only role used by the AI MR-review job."
  type        = bool
  default     = true
}

variable "ai_review_role_name" {
  description = "Name of the AI-review IAM role (must match AI_REVIEW_ROLE_NAME in CI)."
  type        = string
  default     = "platform-ai-review"
}

variable "bedrock_model_arn_patterns" {
  description = "Resource ARN patterns the review role may invoke (inference profiles + foundation models). Defaults cover EU Anthropic models."
  type        = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/anthropic.*",
    "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.*",
  ]
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC + AI-review role (optional). Mirrors the GitLab setup so
# the same review job can run on a GitHub-hosted repo.
# -----------------------------------------------------------------------------

variable "github_ai_review_enabled" {
  description = "Create a GitHub Actions OIDC provider + Bedrock-only role for the AI PR-review workflow."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repo (owner/name) trusted by the GitHub AI-review role, e.g. 'octo/my-repo'."
  type        = string
  default     = ""
}

variable "github_oidc_audience" {
  description = "Audience for GitHub Actions OIDC tokens (aws-actions/configure-aws-credentials uses sts.amazonaws.com)."
  type        = string
  default     = "sts.amazonaws.com"
}

variable "github_ai_review_role_name" {
  description = "Name of the GitHub Actions AI-review IAM role."
  type        = string
  default     = "platform-ai-review-github"
}
