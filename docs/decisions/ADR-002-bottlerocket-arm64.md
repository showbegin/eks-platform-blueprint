# ADR-002 — Bottlerocket on Graviton (ARM64) for EKS nodes

**Status**: Accepted
**Date**: 2026-05

## Context

EKS node group OS and architecture choice affects: container startup time, security surface, cost, and which container images can run. Default Amazon Linux 2023 on x86 is the safe choice but not the optimal one for a container-first platform in 2026.

## Decision

- **OS**: Bottlerocket (`bottlerocket-aws-k8s-1.34-aarch64`)
- **Architecture**: ARM64 (Graviton)
- **Instance type**: `m6g.xlarge` for the dev pool (4 vCPU, 16GB RAM)

## Consequences

**Positive**:
- ~20% cheaper than equivalent x86 (m5.xlarge) for same vCPU/memory.
- Bottlerocket has minimal attack surface: no shell, no package manager, immutable root, automatic in-place updates.
- Bottlerocket boot time is faster than AL2023 — relevant for cluster autoscaling.
- ARM64 is now first-class for the Go, Java, Node.js, and Python ecosystems. Most popular images are multi-arch.

**Negative**:
- Some legacy images are x86-only. Mitigation: build multi-arch images (`docker buildx`) or quarantine x86 workloads to a separate node pool.
- Bottlerocket has no SSH; debugging requires the admin container or `kubectl debug node`. Different muscle memory.
- Smaller community than AL2023 for runbook/Stack Overflow searches.

## Alternatives considered

- **AL2023 on x86 (m5.xlarge)** — most familiar, broadest image compatibility, but ~20% more expensive and larger attack surface.
- **AL2023 on Graviton** — saves cost but keeps full Linux distro overhead.
- **Karpenter instead of managed node groups** — orthogonal. Karpenter is a strong follow-up; this ADR is about node OS/arch only.

## Mitigation for x86-only workloads

A second node group with x86 instances can be added with a `nodeSelector: kubernetes.io/arch: amd64` taint. Not done in dev to keep the cost story simple; documented in `docs/RUNBOOKS.md` as the path forward.
