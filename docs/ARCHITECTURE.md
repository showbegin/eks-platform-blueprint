# Architecture

System overview. For why each piece is the way it is, see [`decisions/`](decisions/).

## Layered view

```
┌─────────────────────────────────────────────────────────────────┐
│  Application layer (Go services, etc.)                          │
│  Built via GitLab CI, packaged with microservice-chart          │
└──────────────┬──────────────────────────────────────────────────┘
               │ HTTPRoute (Gateway API)
┌──────────────▼──────────────────────────────────────────────────┐
│  Edge layer                                                     │
│  Istio Gateway → AWS NLB                                        │
└──────────────┬──────────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────────┐
│  Control plane                                                  │
│  istiod, cert-manager, external-dns, autoscaler                 │
└──────────────┬──────────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────────┐
│  Compute                                                        │
│  EKS 1.34 + Bottlerocket ARM64 nodes                            │
└──────────────┬──────────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────────┐
│  Network — VPC with secondary CIDR for pods                     │
└──────────────┬──────────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────────┐
│  Data — RDS / Aurora / S3 / EFS / SQS                           │
└─────────────────────────────────────────────────────────────────┘
```

## Request flow (sample-service)

1. Client → DNS (Route53) → AWS NLB
2. NLB → Istio Gateway pod
3. Istio Gateway evaluates HTTPRoute → forwards to service ClusterIP
4. Service → Pod (sample-service container)
5. Pod accesses AWS services via IRSA-assumed role (S3, SQS, RDS via secret)

See [ADR-003](decisions/ADR-003-gateway-api-over-ingress.md) for why Gateway API.

## Module layout

Modules numbered with [XXYZ scheme](decisions/ADR-006-xxyz-numbering.md):

| Category | Range | Purpose |
|----------|-------|---------|
| Bootstrap | 00xx | Terraform state backend |
| Foundation | 01xx | VPC, TGW, Route53 |
| Compute | 02xx | EKS, autoscaler, bastion |
| Data | 03xx | RDS, Aurora, S3, EFS |
| Messaging | 04xx | SQS |
| Registry | 05xx | ECR |
| Helm operators | 06xx | cert-manager, Istio, Prometheus, Loki |

Each module is its own Terraform root. See [ADR-010](decisions/ADR-010-per-module-roots.md).

## Cross-cutting concerns

| Concern | Mechanism | Files |
|---------|-----------|-------|
| State | S3 + DynamoDB locking | `0010-state-backend/` |
| Secrets | Vault + CSI Secrets Store driver | `helm/microservice-chart/templates/secretproviderclass.yaml` |
| IAM | IRSA per workload | [ADR-008](decisions/ADR-008-irsa-over-node-iam.md) |
| Tagging | Provider `default_tags` | All `provider "aws"` blocks |
| Policy | OPA + conftest | `policies/opa/` |
| Observability | Prometheus + Grafana + Loki | `0670-kube-prometheus-stack`, `0680-grafana-loki` |

## What this isn't

- **Not a SaaS** — it's a blueprint to be copied and adapted, not a deployed product.
- **Not opinionated about service mesh policies** — Istio is installed; mTLS, AuthorizationPolicy, and RequestAuthentication are left to the consumer.
- **Not a GitOps setup** — `helm upgrade` from CI. ArgoCD/Flux are reasonable evolutions; not the default here. See [ADR-004](decisions/ADR-004-dual-ci.md).

## Further reading

- [`decisions/`](decisions/) — every non-obvious choice
- [`NETWORK_TOPOLOGY.md`](NETWORK_TOPOLOGY.md) — VPC and CIDR layout
- [`CI_CD.md`](CI_CD.md) — pipeline patterns
- [`RUNBOOKS.md`](RUNBOOKS.md) — common ops tasks
