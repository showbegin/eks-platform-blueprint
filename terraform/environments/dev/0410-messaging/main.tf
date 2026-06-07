locals {
  aws_region       = var.aws_region
  environment_name = var.environment

  tags = {
    ops_env              = local.environment_name
    ops_managed_by       = "terraform"
    ops_source_repo      = "eks-platform-blueprint"
    ops_source_repo_path = "terraform/environments/${local.environment_name}/0410-messaging"
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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/0210-eks/terraform.tfstate"
    region = local.aws_region
  }
}

# -----------------------------------------------------------------------------
# SQS Queues — each queue gets a paired DLQ
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  for_each = var.queues

  name                      = "${local.environment_name}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = each.value.kms_master_key_id
  tags                      = local.tags
}

resource "aws_sqs_queue" "main" {
  for_each = var.queues

  name                       = "${local.environment_name}-${each.key}"
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  message_retention_seconds  = each.value.message_retention_seconds
  kms_master_key_id          = each.value.kms_master_key_id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })

  tags = local.tags
}

# -----------------------------------------------------------------------------
# IAM policies for EKS pod consumers (IRSA pattern)
#
# Each queue gets a policy granting the standard producer/consumer actions.
# Pods assume the IRSA role bound to a configured service account.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "queue_access" {
  for_each = var.queues

  name        = "${local.environment_name}-${each.key}-sqs"
  description = "SQS access to ${each.key} for EKS pods"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.main[each.key].arn
      }
    ]
  })

  tags = local.tags
}

# IRSA role per queue (only when service_account is set)
module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.3"

  for_each = { for k, v in var.queues : k => v if v.service_account != null }

  name            = "${local.environment_name}-${each.key}-sqs"
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.oidc_provider_arn
      namespace_service_accounts = ["${each.value.service_account.namespace}:${each.value.service_account.name}"]
    }
  }

  policies = {
    sqs = aws_iam_policy.queue_access[each.key].arn
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudWatch alarms — fire when DLQ has any message
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "dlq_alerts" {
  count = var.alert_email == null ? 0 : 1

  name = "${local.environment_name}-messaging-dlq-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "dlq_email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.dlq_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  for_each = var.queues

  alarm_name          = "${local.environment_name}-${each.key}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when messages appear in ${each.key} DLQ"
  alarm_actions       = var.alert_email == null ? [] : [aws_sns_topic.dlq_alerts[0].arn]

  dimensions = {
    QueueName = aws_sqs_queue.dlq[each.key].name
  }

  tags = local.tags
}
