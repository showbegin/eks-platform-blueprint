# ADR-004 — Dual CI: GitHub Actions for IaC, GitLab CI for applications

**Status**: Accepted
**Date**: 2026-05

## Context

The platform has two CI/CD concerns with very different shapes:
1. **Infrastructure** (Terraform): plan-on-PR, gated apply, OIDC to AWS, low frequency, high blast radius.
2. **Applications** (Docker + Helm): build-test-push-deploy, high frequency, monorepo with N services, per-environment branch deploys, fast iteration.

A single CI tool can do both, but neither does both equally well. GitHub Actions has the cleanest OIDC-to-AWS story but lacks GitLab's `trigger:` + `include:` child pipeline pattern. GitLab CI has the cleanest monorepo dispatch story but its OIDC support is more cumbersome.

## Decision

- **GitHub Actions** for Terraform pipelines. Repository is on GitHub. OIDC role assumption to AWS is native.
- **GitLab CI** for application pipelines. Monorepo apps live on GitLab. SERVICE-variable dispatch routes pipelines to the right service.

The repo includes both as templates, not as live workflows, since the blueprint is meant to be copied into consumer repos that may live on either platform.

## Consequences

**Positive**:
- Each CI does what it's strongest at: GitHub Actions for the IaC review-gated workflow, GitLab CI for monorepo speed.
- OIDC for IaC means zero stored AWS credentials.
- SERVICE-variable dispatch lets one button click force-deploy any service for hotfixes/rollbacks.

**Negative**:
- Two CI systems to maintain. Engineers need to know both.
- Two sets of secrets/variables to keep in sync (account IDs, role ARNs).
- Documentation must explain which tool owns which concern; otherwise the split is confusing.

## Alternatives considered

- **All GitHub Actions** — workable but the monorepo dispatch becomes verbose. Reusable workflows help but don't match GitLab's `trigger:` child pipeline ergonomics.
- **All GitLab CI** — workable but losing GitHub OIDC means using a GitLab-hosted runner with stored AWS creds, which is a security regression.
- **ArgoCD/Flux for apps** — GitOps is a strong alternative for application delivery and may be a future ADR. This blueprint chose imperative deploy via `helm upgrade` to keep the moving parts visible. Migration to ArgoCD documented as future work.

## Documentation

`ci/README.md` explains the rationale and setup for both. The dual-CI choice is one of the most-questioned design decisions; the docs anticipate that.
