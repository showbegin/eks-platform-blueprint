# ADR-001 — Multi-account AWS topology

**Status**: Accepted
**Date**: 2026-05

## Context

EKS workloads need network isolation, IAM blast-radius limits, and cost attribution per environment. The original scaffold deployed everything in one account, which conflated dev/stage/prod permissions, mixed audit logs, and made cost analysis painful.

## Decision

Use AWS Organizations with separate accounts:
- **Management account** — shared services: ECR, Route53 hosted zones, Transit Gateway hub, IAM identity provider
- **Workload accounts** — one per environment (dev, stage, prod), each with its own VPC, EKS cluster, RDS, etc.

Cross-account access is via assumable IAM roles. Cross-VPC connectivity is via Transit Gateway peering.

## Consequences

**Positive**:
- Hard IAM boundary per environment. A compromised dev role cannot touch prod.
- Cost reports per account = per environment, no tagging required.
- CloudTrail logs separated per account, easier audit.
- Independent service quotas per account.

**Negative**:
- More setup: TGW, cross-account roles, ECR pull policies.
- Cross-account Terraform requires `assume_role` provider blocks.
- Engineers must understand which account they're in (mitigated by AWS_PROFILE per env).

## Alternatives considered

- **Single account, IAM permission boundaries** — cheaper but error-prone. Cost attribution requires strict tagging discipline. Quotas shared.
- **Single account, separate VPCs** — solves networking but not IAM blast radius.
- **Multi-region instead of multi-account** — orthogonal; doesn't solve isolation.

## Single-account exception

For evaluation, all `assume_role` blocks are dynamic and skipped when `assume_role_arn = null`. See ADR-009.
