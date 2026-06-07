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

# NOTE on chart_version removal:
#   This module previously installed the upstream `istio/gateway` Helm chart,
#   which produced a manually-managed Deployment + Service. That pattern is
#   incompatible with the workload Helm chart's default routing (Gateway API
#   HTTPRoute against a `platform-gateway` Gateway). Starting with this module
#   revision, the gateway is provisioned via a Gateway API `Gateway` resource;
#   Istio's deployment controller (registered via the `istio` GatewayClass by
#   istiod, see module 0640) auto-provisions the Envoy data-plane Deployment
#   and LoadBalancer Service. There is no longer a chart to version here —
#   the data-plane image version follows istiod's chart_version (module 0640).

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for TLS termination at the LoadBalancer. Set to null for HTTP-only evaluation. The cert is wired onto the auto-provisioned LB Service via spec.infrastructure.annotations on the Gateway."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
