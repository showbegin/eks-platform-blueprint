# ADR-008 — IRSA over shared node IAM role for pod AWS access

**Status**: Accepted
**Date**: 2026-05

## Context

Pods running on EKS nodes can access AWS services via three mechanisms:
1. The node's IAM role (every pod on the node inherits the same permissions).
2. IRSA — IAM Roles for Service Accounts (each ServiceAccount mapped to a dedicated IAM role via OIDC).
3. EKS Pod Identity (newer, similar to IRSA but with simpler setup).

Option 1 is the lazy default and was used by the original scaffold. Every pod on every node could call S3, SQS, ECR, etc. — least-privilege violated, audit log unhelpful.

## Decision

Every workload that needs AWS access gets a dedicated IAM role via IRSA. The role is created in Terraform (typically alongside the resource it accesses, e.g., the SQS module creates the consumer role), trust is scoped to a specific ServiceAccount in a specific namespace, and the policy is minimal.

The Helm chart's `serviceaccount.yaml` template renders the `eks.amazonaws.com/role-arn` annotation when `serviceAccount.roleArn` is set.

## Consequences

**Positive**:
- Least privilege per workload. A compromised pod can only access what its IRSA role permits, not everything the node could.
- CloudTrail logs show the actual workload that called the API, by role name. Audit-friendly.
- Multiple workloads on the same node have isolated AWS identities.

**Negative**:
- More IAM roles to manage. Terraform helps but the count grows linearly with services.
- Setup complexity: OIDC provider, trust policies referencing the OIDC subject, SA annotations. Documented in chart `_helpers.tpl`.
- Engineers used to "just call S3 from any pod" must learn the IRSA pattern.

## Alternatives considered

- **Shared node IAM role** — simple, lazy, insecure. Rejected.
- **EKS Pod Identity** — newer (2023), simpler than IRSA, no OIDC required. Strong alternative. This blueprint chose IRSA because it's more widely understood and has more existing tooling. A future ADR may migrate to Pod Identity.
- **AWS access via separate Lambda/sidecar** — over-engineered for the common case.

## Pattern

The chart's `_helpers.tpl` includes:

```yaml
{{- define "microservice.irsa.roleArn" -}}
arn:aws:iam::{{ .Values.awsAccountId }}:role/{{ .Values.app.name }}
{{- end }}
```

Conventions: role name = service name. Documented in `docs/RUNBOOKS.md`.
