# ADR-003 — Istio + Gateway API as primary ingress, Ingress as fallback

**Status**: Accepted
**Date**: 2026-05

## Context

ingress-nginx has been the de-facto Kubernetes ingress for years, but:
- Active development is slowing; the Kubernetes SIG that maintained it announced the project is in maintenance mode.
- Multi-protocol routing (gRPC, TCP, TLS passthrough) requires hacky annotations.
- Cross-namespace routing is awkward.
- The Kubernetes Gateway API graduated to GA in 2024 and is the explicit successor.

For a blueprint published in 2026, defaulting to ingress-nginx would lock readers into a deprecated path.

## Decision

- **Primary**: Istio service mesh + Istio Gateway exposing the cluster, with workloads routed via `HTTPRoute` resources (Gateway API).
- **Fallback**: keep `Ingress` template in the Helm chart for environments that still run ingress-nginx (migration story).
- The Helm chart selects via `routing.httpRoute.enabled` and `routing.ingress.enabled` flags.

## Consequences

**Positive**:
- Future-proof. Gateway API is the standard going forward.
- HTTPRoute supports cross-namespace references with explicit `ReferenceGrant`. No more annotation tricks.
- Istio adds mTLS, traffic shifting, fault injection, and observability without additional sidecars per workload.
- Single ingress mechanism for L7 HTTP, gRPC, and TCP.

**Negative**:
- Istio control plane is heavyweight (~500MB memory across istiod + gateway pods). Acceptable for production, overkill for tiny clusters.
- Gateway API CRDs must be installed before HTTPRoute resources, requiring apply ordering (handled by 0630-istio-base before workloads).
- Smaller pool of engineers know Gateway API + Istio than ingress-nginx + annotations. Documented in `docs/MIGRATION.md`.

## Alternatives considered

- **AWS Load Balancer Controller + native ALB Ingress** — works on AWS only, ties the platform to ALB. No mesh, no mTLS, no traffic shifting.
- **Cilium Gateway API** — strong alternative, especially with eBPF. Skipped because Istio has wider mindshare among the target audience and existing migration paths.
- **Stay on ingress-nginx** — fastest path but contradicts the blueprint's purpose: showing 2026 best practice.

## Migration story

A separate companion repo migrates a real ingress-nginx setup to this Gateway API design. See the `MIGRATION.md` doc and the planned Post 2.
