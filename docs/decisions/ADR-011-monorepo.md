# ADR-011 — Monorepo blueprint over distributed module repos

**Status**: Accepted
**Date**: 2026-05

## Context

A common architectural recommendation for mature platform teams is to publish each Terraform module as an **independently-versioned repository**, referenced via the Terraform `source = "git::..."` or registry pattern. The "platform team" owns the module repos, "app teams" consume specific versions, and module changes ship via semver bumps.

This is the right shape at scale. It is not the right shape for a published blueprint.

## Decision

This repository is a **monorepo**. Modules, environments, the Helm chart, CI templates, the sample service, and documentation all live in one tree.

```
eks-platform-blueprint/
├── terraform/      # modules + envs
├── helm/           # chart
├── ci/             # CI/CD templates
├── examples/       # sample service
├── docs/           # ADRs + guides
└── scripts/        # ops scripts
```

## Consequences

**Positive**:
- **Clarity for readers** — relationships between module, chart, CI, and example are visible in one place. A reviewer can trace from `helm/microservice-chart/values.yaml` to `terraform/environments/dev/0210-eks/` in one click.
- **Atomic changes** — when a chart change requires a Terraform module update, both ship in the same PR. No multi-repo dance.
- **Lower evaluation friction** — readers clone one repo to evaluate the whole platform.
- **Self-contained portfolio artifact** — the repo stands on its own as evidence of architectural thinking.

**Negative**:
- **No semver per module** — consumers can't pin to "v2.3.0 of the VPC module." They copy a snapshot or reference a Git tag for the whole repo.
- **Module reuse outside the blueprint requires copying** — there's no `terraform-aws-platform-vpc` module to pull in.
- **Repository becomes large** as more modules are added.
- **Doesn't model "platform team owns modules, app team consumes" governance** — both live together.

## Alternatives considered

- **Distributed: separate repo per module, semver releases**. Production end-state for a real platform team. Rejected for the blueprint because the cost of multi-repo coordination outweighs the benefit when the goal is clarity, not consumption-at-scale.

- **Hybrid: monorepo for most, separate repos for sensitive or stable modules**. Defensible but adds asymmetry that confuses readers.

- **Module registry (Terraform Cloud / private registry)**. Same problem as distributed repos plus a registry dependency.

## When this might evolve

If the blueprint becomes the basis for a real platform product with consumers, the modules under `terraform/environments/<env>/<XXYZ>/` would migrate to dedicated repos with semver. The blueprint would then be a thin "live" repo referencing the modules.

For the public blueprint, monorepo is the right choice and the trade-offs are explicit.
