# ADR-003 — Istio + Gateway API as primary ingress, Ingress as fallback

**Status**: Accepted — **validated on live clusters, 2026-09**
**Date**: 2026-05 (updated 2026-09 after a real dual-run migration)

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
- Smaller pool of engineers know Gateway API + Istio than ingress-nginx + annotations.

## Alternatives considered

- **AWS Load Balancer Controller + native ALB Ingress** — works on AWS only, ties the platform to ALB. No mesh, no mTLS, no traffic shifting.
- **Cilium Gateway API** — strong alternative, especially with eBPF. Skipped because Istio has wider mindshare among the target audience and existing migration paths.
- **Stay on ingress-nginx** — fastest path but contradicts the blueprint's purpose: showing 2026 best practice.

## Validated in production (2026-09)

This decision was executed as a real migration on live clusters carrying traffic — ingress-nginx → Istio Gateway API, gateway-only (no mesh, no sidecars). The lessons below are what the migration taught that the original decision did not anticipate. They are why the chart and runbooks look the way they do.

### Dual-run is the whole safety story
Stand the Istio gateways up *beside* nginx, keep both ingress paths live, and migrate **one host at a time** by repointing DNS — rollback is always one DNS change away. The gateways carry zero real traffic until you cut a host's DNS to them. This is exactly what the chart's `routing.httpRoute.enabled` + `routing.ingress.enabled` dual flags exist for: during migration you enable **both**.

### The HTTPRoute template must be CRD-capability-gated
`routing.httpRoute.enabled` is a promoted value (dev → stage → prod share chart values), but the Gateway API CRDs only exist where the platform layer is installed. Gating the template on `.Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1"` (not just the flag) lets `httpRoute.enabled=true` promote safely to clusters that are still on ingress-nginx — it renders a no-op there instead of failing the deploy with `no matches for kind "HTTPRoute"`. See `helm/microservice-chart/templates/httproute.yaml`.

### The CLB→NLB chain — four gotchas, each invisible to `terraform plan`
Bringing the gateways up on a modern NLB (rather than the legacy in-tree Classic ELB) surfaced four issues **in sequence**, and every one passed `terraform plan`/`validate` and only failed against the live Kubernetes/AWS API:
1. **AWS Load Balancer Controller not installed** → gateways come up as Classic ELBs. Install the controller first.
2. **Type-swap doesn't auto-replace** → changing the LB type needs the correct modern annotations (`nlb-target-type: ip`, explicit `scheme`, drop CLB-only knobs) to actually take.
3. **Subnet auto-discovery fails** without the `kubernetes.io/role/elb` (public) / `role/internal-elb` (private) subnet tags. The "proper fix" (tag them in the VPC stack) can be a trap if that stack's plan is a destroy/recreate — **read the plan for what it destroys, not just what it adds**; pin subnets on the gateway as a safe workaround.
4. **Controller IAM policy lag** → a canned "LB controller policy" can trail the controller version by a few actions (e.g. `DescribeListenerAttributes`). Vendor the **official IAM policy JSON pinned to the controller release** so IAM stays in lockstep.

Recurring lesson: **a green `terraform apply` is not "it works"** for anything whose real effect lives in the Kubernetes API or a cloud control plane. Verify the runtime, not the plan.

### The Gateway CRD caps `infrastructure.annotations` at 8
`spec.infrastructure.annotations` on the Gateway v1 CRD has `maxProperties: 8` — a server-side rule invisible to plan/validate. Five base NLB annotations + four TLS-at-LB annotations = nine → rejected at apply. Drop one non-essential annotation to fit.

### ACM-at-LB means no cert regression
Terminating TLS at the load balancer with an ACM wildcard, reused on the gateway's NLB, means migrated hosts serve the **same certificate** they did on nginx. cert-manager/Let's-Encrypt does not need to be reproduced on the gateway path. (Corollary: a cert check alone does **not** prove you're hitting the gateway — the issuer is identical on both LBs; check the resolved target.)

### "Migrated" and "retired" are different milestones
The non-obvious wall: every service can serve through the gateway and DNS can point nowhere near nginx — and you still can't remove nginx. Under a shared-values promotion model, the same value that safely *enables* the new route (`httpRoute.enabled=true`, CRD-gated) would, if you also set `ingress.enabled=false`, promote that disable to environments that have **no** gateway yet — black-holing them. So the honest end state for a single environment is **dual-config held deliberately**: both enabled, all real traffic on the gateway, nginx kept as a rollback path and as the price of promotion-safety. The redundant load balancer only comes out once *every* environment has the gateway, or once the chart varies `ingress.enabled` per environment. **That gap is owned by the promotion topology, not the ingress technology.**
