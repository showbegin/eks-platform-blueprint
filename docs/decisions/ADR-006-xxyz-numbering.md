# ADR-006 — XXYZ module numbering scheme

**Status**: Accepted
**Date**: 2026-05

## Context

Terraform modules in a multi-tier platform must be applied in a specific order: VPC before EKS, EKS before Helm operators, cert-manager before Istio gateway (so the gateway can use TLS). Without an explicit ordering convention, this dependency information lives only in the engineer's head or in a separate orchestration tool (terragrunt, Atlantis, Spacelift).

## Decision

Number every module with a 4-digit prefix `XXYZ`:

- **XX** (hundreds digit): top-level category. Categories grouped by 100s.
  - `00xx` Bootstrap (state backend)
  - `01xx` Foundation (VPC, TGW, Route53)
  - `02xx` Compute (EKS, autoscaler, bastion)
  - `03xx` Data (S3, RDS, Aurora, EFS)
  - `04xx` Messaging (SQS)
  - `05xx` Registry (ECR)
  - `06xx` Helm operators (cert-manager, external-dns, Istio, Prometheus, Loki)
- **Y** (tens digit): module within a category. Increment by 10.
- **Z** (ones digit): sub-modules of the parent. `0` is the parent, `1-9` are children.

Apply order is the natural numerical sort.

## Consequences

**Positive**:
- Apply order is visible from `ls`. No external tooling required.
- Dependencies between modules are encoded in the prefix. Reviewers know at a glance that `0210-eks` must apply before `0610-cert-manager`.
- Room for growth: 9 slots per category, 9 sub-slots per module, infinite categories.
- Onboarding engineers see the structure immediately.

**Negative**:
- Renumbering is painful if categories need reorganizing.
- The scheme is novel; engineers familiar with terragrunt or Atlantis may push back.
- Long directory names: `0670-kube-prometheus-stack` instead of `prometheus`.

## Alternatives considered

- **Alphabetical** — readable but loses ordering information.
- **Terragrunt with explicit `dependencies`** — solves ordering but adds a tool layer. Terragrunt is a reasonable choice; this blueprint preferred to keep the dependency in the directory listing.
- **Single-digit prefix `1-9`** — runs out of slots quickly; 4 digits give room.

## Convention

When adding a module, pick the smallest unused number in the right category. If a category fills up, increment to the next free `XX00`.
