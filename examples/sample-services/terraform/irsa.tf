# IRSA roles for the producer + consumer demo.
#
# Demonstrates the platform's least-privilege pattern:
#   - producer role: SQS:SendMessage on the queue, nothing else
#   - consumer role: SQS:Receive/Delete on queue + DLQ + S3:PutObject on bucket
#
# Each role is bound to a specific Kubernetes ServiceAccount via OIDC trust.

# Queue ARNs from the messaging module's remote state
locals {
  queue_arn = data.terraform_remote_state.messaging.outputs.queue_arns[local.queue_key]
  dlq_arn   = replace(local.queue_arn, local.queue_name, "${local.queue_name}-dlq")
}

# -----------------------------------------------------------------------------
# Producer — write-only on the queue
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "producer" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [local.queue_arn]
  }
}

resource "aws_iam_policy" "producer" {
  name        = "${local.environment_name}-sample-producer"
  description = "Producer pod IRSA — SQS SendMessage on ${local.queue_name}"
  policy      = data.aws_iam_policy_document.producer.json
}

module "producer_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.3"

  name            = "${local.environment_name}-sample-producer"
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.oidc_provider_arn
      namespace_service_accounts = ["sample-producer:sample-producer"]
    }
  }

  policies = {
    sqs = aws_iam_policy.producer.arn
  }
}

# -----------------------------------------------------------------------------
# Consumer — receive/delete on queue + DLQ access + S3 write
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "consumer" {
  statement {
    sid    = "SQSReceiveDelete"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [local.queue_arn, local.dlq_arn]
  }

  statement {
    sid    = "S3PutProcessed"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = ["${aws_s3_bucket.processed.arn}/*"]
  }
}

resource "aws_iam_policy" "consumer" {
  name        = "${local.environment_name}-sample-consumer"
  description = "Consumer pod IRSA — SQS Receive/Delete + S3 PutObject"
  policy      = data.aws_iam_policy_document.consumer.json
}

module "consumer_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.3"

  name            = "${local.environment_name}-sample-consumer"
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.oidc_provider_arn
      namespace_service_accounts = ["sample-consumer:sample-consumer"]
    }
  }

  policies = {
    consumer = aws_iam_policy.consumer.arn
  }
}
