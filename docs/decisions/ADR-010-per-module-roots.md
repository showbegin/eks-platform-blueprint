# ADR-010 — Per-module Terraform roots over single-root-per-environment

**Status**: Accepted
**Date**: 2026-05

## Context

A common Terraform structure shown in tutorials and "best practices" diagrams uses a single root module per environment:

```
environments/
├── dev/
│   ├── main.tf       # calls module.networking, module.compute, module.database, ...
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── backend.tf
└── prod/
    └── ...
```

This pattern is appealing for small projects (~30 resources) but breaks at scale.

## Decision

Each subsystem is its own Terraform **root module** per environment. State is per-module. Apply order is encoded in the [XXYZ numbering scheme (ADR-006)](ADR-006-xxyz-numbering.md):

```
terraform/environments/dev/
├── 0110-vpc/         # own backend.tf, own state
├── 0210-eks/         # own backend.tf, own state
├── 0310-s3/          # own backend.tf, own state
├── 0610-cert-manager/
└── ...
```

Cross-module references use `terraform_remote_state` data sources to read outputs from the S3 backend.

## Consequences

**Positive**:
- **Small state per module** — 10–30 resources vs. 200+ in a single-root design. State operations are fast.
- **Independent apply** — a VPC change does not replan EKS. A failed cert-manager install does not corrupt VPC state.
- **Smaller blast radius** — `terraform destroy` in one module cannot accidentally take down others.
- **Faster plan times** — relevant in CI where each module's plan is a separate matrix job.
- **Stages of apply** — `0010 → 0110 → 0210 → ...` can be applied in CI in dependency order with a clean matrix; partial applies are recoverable.
- **Module-level version pinning** — different envs can run different module versions during rollouts.

**Negative**:
- **More boilerplate** — each module has its own `backend.tf`, `variables.tf`, `terraform.tfvars`. Mitigated by the consistent shape and `terraform.tfvars.example` templates.
- **No automatic dependency graph** — XXYZ encodes ordering manually. Engineers must understand it.
- **Cross-module references via remote state** — slightly more verbose than local module references.
- **Initial setup cost** — the S3 backend (state + DynamoDB lock) must exist before any module can apply. The `0010-state-backend` bootstrap module handles this.

## Alternatives considered

- **Single root per env** (the pattern shown in most tutorials): one `main.tf` per env that wires all modules. Rejected because:
  - State file becomes huge (200+ resources in production).
  - Any change replans the entire environment (slow plan, slow review).
  - Lock contention: only one engineer can apply at a time.
  - Failed apply on one component can leave the entire state in a partially-applied state.

- **Terragrunt with per-component `terragrunt.hcl`** files: strong alternative, achieves the same isolation with less boilerplate via `inputs` and `dependency` blocks. Rejected for this blueprint because:
  - Adds a tool layer that some teams don't have.
  - Plain Terraform with XXYZ + S3 remote state is portable to any team.
  - Documenting the choice (this ADR) is more useful than adopting another DSL.

- **Atlantis or Spacelift orchestration**: orchestration tools that handle the dependency graph at the platform level. Orthogonal — could be added on top of either structure.

## When this might evolve

If the blueprint were extended into a SaaS-scale platform with hundreds of modules and a dedicated platform team, Terragrunt or Atlantis would become attractive. For the current scope (one blueprint, one team consuming it), plain Terraform with XXYZ stays clearer.
