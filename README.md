# eks-platform-blueprint

> An end-to-end reference for spinning up a production-grade AWS platform on EKS — multi-account Terraform with Transit Gateway, core operators (cert-manager, external-dns, Istio Gateway API, Prometheus, Loki) via Terraform-managed Helm, a reusable microservice chart, and a dual-CI pattern (GitHub Actions for infrastructure, GitLab CI for applications).

> [!NOTE]
> **Status: Phase 7 launch.** Repository validated end-to-end on a clean AWS account during Phase 6 PoC (May 2026). Twelve issues found and catalogued; the structural ones are fixed in the version you see. Control-validation pass scheduled before public flip. See [Validation status](#validation-status) below for the full picture.

## Who this is for

This blueprint is an **Internal Developer Platform (IDP) pattern** for teams running 3–30 microservices on EKS. It optimizes for two things at once:

- **Monorepo integrity** — one repo holds Terraform modules, Helm chart, services, ADRs, OPA policies, CI templates. A platform-level change (new tag taxonomy, chart upgrade, new policy) lands in a single PR and applies everywhere consistently.
- **Per-service isolation** — separate Terraform state per module, separate IRSA role per workload, separate Kubernetes namespaces, scoped IAM policies. The producer in [`examples/`](examples/) cannot read its own queue — and that boundary is enforced at the IAM layer, not by convention.

### When this fits

- You ship platform changes that need to land everywhere atomically (new tags, new policies, chart upgrade)
- You can't tolerate one service's IAM compromise reaching another
- You want a paved path for new services: one chart + standard CI + standard observability
- You have (or are growing) a small platform team responsible for the EKS substrate
- Compliance pressure makes "every service has its own role with minimum-necessary permissions" non-negotiable

### When this is overkill

- Fewer than ~5 services with no platform team — a single CDK app or simpler tooling is cheaper
- Pure batch / event-driven workload — ECS/Fargate or Step Functions beats this
- You explicitly want polyrepo-per-service ownership — this blueprint's atomic-change story is the wrong tradeoff

The architectural opinion is **opinionated paved path with strict service boundaries**. If that resonates, the rest of this README walks you through the implementation.

## Why this exists

In the AI-assistance era, a corporate microservice estate of 5–30 services can be responsibly owned by **one senior engineer** — when the organization-from-scratch is right. AI accelerates the work, but it doesn't carry it. The architectural choices still need to hold up; the operational discipline still has to be paid; the security boundaries still have to be enforced at the IAM layer, not by convention.

This blueprint is the operating model I converged on after running this pattern at production scale: monorepo integrity for atomic platform changes, per-service isolation for blast-radius containment, multi-account Terraform with shared Transit Gateway backbone, EKS with the standard core operators (cert-manager, external-dns, Istio Gateway API, Prometheus, Loki) via Terraform-managed Helm, a reusable microservice chart for application deployment, and a monorepo CI/CD pattern demonstrating both GitHub Actions (for infrastructure, with OIDC) and GitLab CI (for applications, with a per-service `SERVICE`-variable dispatch pattern).

Patterns here are validated on a live AWS PoC cluster before publication ([see below](#validation-status)). The CI dispatch scripts are the distilled version of what I use daily to ship microservices across dev / stage / prod environments.

The pitch is **architectural coherence + production-validated + specific engineering judgment** (dual-CI for resilience-not-preference, Gateway API migration from EOL ingress-nginx, multi-account Transit Gateway topology), not tool novelty.

The architectural choices are stated as trade-offs throughout, not universal claims — the README sections [`Who this is for`](#who-this-is-for) and [`When this is overkill`](#when-this-is-overkill) are deliberately at the top, so you can decide quickly whether this fits your context before reading the rest.

## What's distinctive

- **Multi-account topology** — separate AWS accounts for management, dev, stage, prod; shared Transit Gateway in the management account; consistent VPC pattern (10.0.0.0/16 primary + secondary CIDRs for EKS workers). [Single-account fallback](#deployment-modes) is fully supported for evaluation, with the same code (ADR-009).
- **Istio Gateway API instead of ingress-nginx** — ingress-nginx is EOL; this repo ships the forward-looking migration with rationale captured in [`docs/decisions/ADR-003-gateway-api-over-ingress.md`](docs/decisions/ADR-003-gateway-api-over-ingress.md) and validation in [`lab/poc-validation.md`](lab/poc-validation.md).
- **Dual-CI for resilience, not preference** — GitHub holds the reproducible IaC code as a regional-failure backup. If self-hosted GitLab becomes unavailable across the AWS region, GitHub has the IaC to bring up reproducible environments in another region. GitLab is the day-to-day driver: CI + CD, monorepo-friendly, per-service `SERVICE`-variable dispatch. The split isn't preference — it's a deliberate resilience choice. Documented in [`docs/decisions/ADR-004-dual-ci.md`](docs/decisions/ADR-004-dual-ci.md).
- **Shared infra where consolidation pays, isolated where blast-radius matters** — Route53, VPC primitives, Transit Gateway, Vault are shared (single point of management, cost reduction). EKS clusters are per-environment (blast-radius separation). IRSA roles, namespaces, IAM policies are per-service (compromise containment). The boundary is the meta-pattern that makes the rest of the choices coherent.
- **PoC validation in `lab/`** — twelve issues found by standing the repo up from scratch on a clean AWS account, including six real bugs in the code. All structural ones are fixed; the rest are documented as known limitations. See [`lab/poc-validation.md`](lab/poc-validation.md). The version you clone is the one that survived being broken.

## Repository layout

```
eks-platform-blueprint/
├── terraform/                         # Multi-account IaC
│   ├── backend/                       # 0010-state-backend (S3 + DynamoDB, shared across envs)
│   ├── accounts/management/           # Management account modules (TGW, shared ECR)
│   └── environments/                  # Per-env modules (dev, stage, prod)
│       ├── dev/                       # All categories represented
│       ├── stage/                     # Same shape, scaled-down
│       └── prod/                      # Adds Aurora HA, internal Istio gateway
├── helm/microservice-chart/           # Reusable application chart (Gateway API HTTPRoute)
├── ci/
│   ├── github-actions/                # Terraform pipeline (OIDC, plan-on-PR, apply-on-merge)
│   └── gitlab-ci/                     # Application CI templates + per-env scripts
│       ├── templates/                 # Reusable build / deploy / rollback / e2e templates
│       └── scripts/                   # Per-env account/role/domain dispatch
├── examples/                          # End-to-end demo: producer + consumer
│   ├── sample-producer/               # HTTP → SQS (write-only IRSA)
│   ├── sample-consumer/               # SQS → S3 (read+write IRSA)
│   └── sample-services/terraform/     # Demo SQS + S3 + scoped IRSA roles
├── lab/                               # Live AWS PoC validation artifacts (Phase 6)
└── docs/                              # Architecture, network topology, ADRs
    └── decisions/                     # ADR-001 through ADR-008
```

## Module numbering — `XXYZ` scheme

Modules are numbered with a 4-digit prefix that encodes both **apply order** (lower = applied first) and **semantic grouping** (categories share a prefix). This makes the dependency graph visible from the directory listing, without forcing it through tooling.

- **XX** (hundreds): top-level category. Incremented by 100 between categories, leaving 9 module slots per category and room for new categories.
- **Y** (tens): specific module within the category. Incremented by 10, leaving room for sub-modules.
- **Z** (ones): sub-modules dependent on the parent module (0 = main module, 1-9 = dependents).

Categories:

| Prefix | Category | Modules in this repo |
|--------|----------|---------------------|
| `00xx` | Bootstrap | `0010-state-backend` |
| `01xx` | Foundation (network + DNS) | `0110-vpc`, `0120-tgw-attachment`, `0130-route53-hostedzone` |
| `02xx` | Compute | `0210-eks`, `0220-eks-cluster-autoscaler`, `0230-bastion` |
| `03xx` | Data (relational, object, file) | `0310-s3`, `0320-rds`, `0330-aurora` (prod), `0340-efs` (prod, optional) |
| `04xx` | Messaging | `0410-messaging` (SQS + Lambda) |
| `05xx` | Registry | `0510-ecr` |
| `06xx` | Helm operators + Gateway API | `0600-gateway-api-crds`, `0610-cert-manager`, `0620-external-dns`, `0630-istio-base`, `0640-istiod`, `0650-istio-gateway`, `0660-istio-gateway-internal`, `0670-kube-prometheus-stack`, `0680-grafana-loki` |

Apply order within an environment is the numerical sort. The Helm operators (`06xx`) depend on EKS (`0210`) being applied first; the Helm provider in those modules reads cluster details from remote state. `0600-gateway-api-crds` installs the standard Gateway API CRDs (using a pinned upstream release) and must precede `0640-istiod` so Istio's Gateway API support has the CRDs available at install time.

When adding a new module, pick the smallest unused number in the right category. If all slots in a category are used (rare), increment the category prefix to the next free `XX00`.

### Per-module deployment status (Phase 6 PoC)

The following modules were applied end-to-end during PoC:

| Module | Applied | Notes |
|--------|---------|-------|
| `0010-state-backend` | ✅ | S3 + DynamoDB; backend bucket retained across teardown for next apply |
| `0110-vpc` | ✅ | Single-account mode; 26 resources |
| `0210-eks` | ✅ | 49 resources; default StorageClass (`gp3`) provisioned in-module post-PoC |
| `0600-gateway-api-crds` | ⏳ | Module written post-PoC (Gateway API CRDs were applied manually during PoC); control-validation will be the first apply |
| `0610-cert-manager` | ✅ | Switched to `kubectl_manifest` for ClusterIssuers post-PoC to avoid plan-time CRD validation race |
| `0630-istio-base` | ✅ | Chart 1.30.0 |
| `0640-istiod` | ✅ | Chart 1.30.0 |
| `0650-istio-gateway` | ✅ | Rewritten post-PoC as Gateway API resource (no Helm release); legacy chart removed |
| `0660-istio-gateway-internal` | ⏳ | Same shape as 0650, internal LB; control-validation will be the first apply |
| `0670-kube-prometheus-stack` | ✅ | Chart 86.1.0; 21/21 targets green |
| `0220-eks-cluster-autoscaler` | ⏸ | Optional; not applied during PoC |
| `0620-external-dns` | ⏸ | Optional; not applied during PoC (no public domain in PoC scope) |
| `0680-grafana-loki` | ⏸ | Chart in maintenance mode; future migration to `grafana/loki` chart planned |
| `0230-bastion` | ⏸ | Optional; not applied during PoC |

Legend: ✅ applied + verified · ⏳ pending control-validation · ⏸ optional / not exercised

The pending modules (⏳) and the structural fixes in the ✅ modules (cert-manager, istio-gateway, eks) all land together in the Sat Jun 6 control-validation pass. That pass's outcome is the final green-light for the public flip.

## Quick evaluation

**No AWS account?** Browse the code — the architecture is readable from the directory structure and module cross-references alone.

**Have an AWS account?** See [`quickstart/README.md`](quickstart/README.md) for a single-account deployment guide. No multi-account org, custom domain, or self-hosted GitLab required.

### Deployment modes

| Mode | Requirements | What works |
|------|-------------|------------|
| **Code review only** | Git | Full architecture inspection |
| **Single-account** | 1 AWS account, Terraform, Helm | VPC → EKS → Istio → sample service |
| **Multi-account** (production) | AWS Organizations, 3+ accounts, domain | Everything including TGW, Route53, ACM |

### Cost estimate (single-account, full stack)

| Resource | Monthly |
|----------|---------|
| EKS control plane | $73 |
| 2× m6g.xlarge nodes | $226 |
| NAT Gateway (1 AZ) | $33 |
| EBS storage (2× 200GB gp3) | $32 |
| S3 + DynamoDB (state) | ~$1 |
| **Total** | **~$365/mo** |

**Weekend evaluation**: deploy Friday, destroy Sunday → **~$22**.

## Validation status

This blueprint was stood up from scratch on a clean AWS account during Phase 6 PoC (May 2026), deployed end-to-end, then destroyed. The destructive-test approach surfaces issues that pass-only tests miss.

**Findings**: twelve issues catalogued across the run.

- **Six were real bugs in the code** (the kind that would have broken the quickstart on someone else's cluster, not mine). All six structural ones are fixed in the code you see in this commit.
- **Three were configuration choices** that needed explicit `tfvars` overrides (VPC CIDR, EKS API endpoint, state bucket name) — documented in [`quickstart/README.md`](quickstart/README.md).
- **Two were upstream-dependency / chart-schema issues** sidestepped by version bumps to current stable.
- **One** (Finding 11 — major-version bumps for `terraform-aws-modules/eks` and `vpc` modules) is **deferred to a separate validated PR** post-launch.

The full finding-by-finding catalogue, with reproduction steps, root cause, and fix evidence, ships in this repo at [`lab/poc-validation.md`](lab/poc-validation.md). It's intended as a reader-facing artifact: if you adopt this blueprint and hit a similar issue, the lab doc tells you where to look.

**Control-validation pass**: a fresh apply on a clean account is scheduled before the public flip, to confirm the polished code reproduces the green path end-to-end. That run's outcome will be appended to `lab/poc-validation.md`.

**What this is not**: a claim of production-readiness. The PoC was a 100-hour shakedown on a single account, not a multi-month operational track record. The blueprint encodes the architectural and security choices I'd make on day one of a new microservice estate; calibrating it to your specific compliance, scale, and operational requirements is your work.

## Getting started

For a guided walkthrough deploying the core platform in a single AWS account:

→ **[`quickstart/README.md`](quickstart/README.md)**

For production multi-account deployments, see the full documentation (Phase 5).

## Documentation

| Document | Purpose |
|----------|---------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System overview, request flow, layered view |
| [`docs/NETWORK_TOPOLOGY.md`](docs/NETWORK_TOPOLOGY.md) | VPC, secondary CIDR, multi-account TGW |
| [`docs/CI_CD.md`](docs/CI_CD.md) → [`ci/README.md`](ci/README.md) | Pipeline patterns, dual-CI rationale |
| [`docs/RUNBOOKS.md`](docs/RUNBOOKS.md) | Common ops tasks |
| [`docs/MIGRATION.md`](docs/MIGRATION.md) | Migration paths into this blueprint |
| [`docs/decisions/`](docs/decisions/) | 11 ADRs explaining every non-obvious choice |
| [`policies/`](policies/) | OPA policies (tagging, encryption, network rules) |
| [`scripts/`](scripts/) | Operations scripts (validate, plan-all, destroy-all) |

## License

[MIT](LICENSE).

## Acknowledgements

The initial repository scaffold was inspired by the Pluralsight course material at [ManagedKube/kubernetes-ops](https://github.com/ManagedKube/kubernetes-ops). This codebase has been substantially rewritten — native AWS Terraform modules in place of the original dependency tree, S3 backend in place of Terraform Cloud, multi-account Transit Gateway topology, Istio Gateway API in place of EOL ingress-nginx, dual-CI pattern (GitHub Actions for infrastructure + GitLab CI for applications) — and reorganized with a `XXYZ` hierarchical numbering scheme that makes apply order and module grouping explicit.

## Author

Built and maintained by [@showbegin](https://github.com/showbegin) — senior DevOps / Platform Engineer. Open to contract work and consulting; reach out via LinkedIn.
