# ADR-009 — Single-account evaluation mode alongside multi-account production

**Status**: Accepted
**Date**: 2026-05

## Context

The blueprint's production target is multi-account (ADR-001). However, evaluators — engineers reading the repo to decide if it's worth adopting, recruiters reviewing the portfolio, candidates running through the code in interviews — usually have access to a single AWS account at most.

A blueprint that requires AWS Organizations setup, three accounts, Transit Gateway, and a delegated DNS zone before anything can be run has a high evaluation barrier. Most readers won't bother.

## Decision

Make every cross-account dependency optional, defaulting to single-account behavior:

- `assume_role_arn` defaults to `null` in every module. The `assume_role` provider block uses `dynamic` so it's skipped entirely when null.
- `acm_certificate_arn` defaults to `null` in `0650-istio-gateway`. When null, the gateway exposes HTTP only — no domain or cert needed.
- `acme_email` defaults to `null` in `0610-cert-manager`. When null, only a self-signed `ClusterIssuer` is created. Workloads can still get certs from `cert-manager`, just self-signed.

The quickstart README (`quickstart/README.md`) walks through a subset of modules that, with the above optionals, deploys a working platform in one account with no domain.

## Consequences

**Positive**:
- Evaluation barrier drops from "set up AWS Organizations" to "have an AWS account."
- Cost transparency makes the evaluation tangible: ~$22 for a weekend. Documented up front.
- Single-account mode is a real config, not a docs-only suggestion. Tested in CI.
- Multi-account remains the documented production pattern. Evaluation mode does not contaminate it.

**Negative**:
- More variable defaults to track. Each optional must be tested with both null and set values.
- Documentation must explain when to use which mode and what's missing in evaluation mode.
- The `dynamic` provider blocks are slightly less obvious than static `assume_role` blocks.

## Alternatives considered

- **Separate quickstart fork** — a completely separate, simplified repo for evaluation. Rejected: maintenance burden, drift between the two.
- **Multi-account only, with mock instructions** — kept honest but raised the barrier too high.
- **Single-account only** — the inverse, too limiting for the production target.

## Validation

Single-account mode is validated end-to-end on a real cluster (separate cluster in the staging AWS account) before the repo is published. See `lab/poc-validation.md`.
