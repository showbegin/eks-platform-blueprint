# ADR-007 — Single parametrized Helm chart for all microservices

**Status**: Accepted
**Date**: 2026-05

## Context

A platform with N microservices can choose between:
1. One Helm chart per service (each service ships its own chart).
2. A single shared chart parametrized via values (all services use the same chart, supplying their values).
3. A base chart + per-service overrides (Kustomize-style overlays, or Helm library charts).

Option 1 is flexible but creates N×M maintenance: every cross-cutting change (new label, new probe pattern, new annotation) requires N updates. Option 3 has merit but adds template complexity.

## Decision

Single chart at `helm/microservice-chart/` consumed by all services. Each service supplies a `helm-values.yaml` override file.

The chart supports the platform's primitives:
- Deployment + Service + ServiceAccount with optional IRSA
- Gateway API HTTPRoute (primary) + Ingress (legacy fallback)
- Vault SecretProviderClass (optional)
- Prometheus ServiceMonitor (optional)
- Standard probes, resources, replicas, image references

## Consequences

**Positive**:
- One place to update conventions. Adding a new label, changing probe defaults, fixing an annotation — single PR.
- Consistency across services is enforced by the chart shape.
- Onboarding a new service is a values file, not a chart authoring exercise.
- Easier to audit: every service runs the same templating.

**Negative**:
- Constraints on what services can do. A service needing an unusual deployment shape (DaemonSet, StatefulSet, multi-container with different probes) doesn't fit and must either escape the chart or extend it.
- The chart values file becomes wide. Discipline required to keep it documented.
- All services share the chart's release cadence. A breaking chart change cascades.

## Alternatives considered

- **Per-service charts** — flexibility at the cost of N×M maintenance.
- **Helm library chart** — solves cross-cutting concerns but each service still has its own chart shell. More moving parts.
- **Operators (CRD-based)** — overkill for this scope. Reasonable for >50 services or when complex lifecycle management is needed.

## Escape hatches

A service that genuinely doesn't fit the chart can ship its own chart and live alongside. The blueprint doesn't forbid this; it prefers the shared chart as the default.
