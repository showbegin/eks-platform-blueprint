# Architecture Decision Records

This directory captures the non-obvious decisions in the platform's design. Each ADR explains the context, the decision, the consequences, and what was rejected.

ADRs exist because reviewers need to distinguish intentional design from copy-paste. They also exist because future-me will forget why the current shape was chosen.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [001](ADR-001-multi-account-topology.md) | Multi-account AWS topology | Accepted |
| [002](ADR-002-bottlerocket-arm64.md) | Bottlerocket on Graviton (ARM64) for EKS nodes | Accepted |
| [003](ADR-003-gateway-api-over-ingress.md) | Istio + Gateway API as primary ingress | Accepted |
| [004](ADR-004-dual-ci.md) | Dual CI: GitHub Actions for IaC, GitLab CI for apps | Accepted |
| [005](ADR-005-native-aws-modules.md) | Native AWS Terraform modules over ManagedKube wrapper | Accepted |
| [006](ADR-006-xxyz-numbering.md) | XXYZ module numbering scheme | Accepted |
| [007](ADR-007-single-helm-chart.md) | Single parametrized Helm chart for all microservices | Accepted |
| [008](ADR-008-irsa-over-node-iam.md) | IRSA over shared node IAM role | Accepted |
| [009](ADR-009-single-account-evaluation-mode.md) | Single-account evaluation mode | Accepted |
| [010](ADR-010-per-module-roots.md) | Per-module Terraform roots over single-root-per-environment | Accepted |
| [011](ADR-011-monorepo.md) | Monorepo blueprint over distributed module repos | Accepted |

## Format

Each ADR follows: **Context → Decision → Consequences → Alternatives considered**.

If a future change reverses a decision, the old ADR stays (Status: Superseded by ADR-NNN) and a new ADR documents the reversal. ADRs are not deleted.
