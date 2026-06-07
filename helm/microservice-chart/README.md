# microservice-chart

Reusable Helm chart for deploying microservices on EKS. Designed to pair with the
infrastructure modules in this repository (Istio Gateway API, IRSA, Vault CSI,
kube-prometheus-stack).

## Features

- **Gateway API HTTPRoute** as the modern routing primitive (Ingress kept as legacy fallback)
- **IRSA** service account annotation derived from `awsAccountId` + `environment` + `roleSuffix`
- **Vault CSI** secret injection at `/mnt/secrets-store`
- **Health probes** (readiness, liveness, startup) — disabled by default, opt-in per service
- **ServiceMonitor** for Prometheus scraping (kube-prometheus-stack discovery)
- **Per-environment hostAliases** for cross-VPC/private DNS scenarios

## Quick start

```bash
helm upgrade --install sample-service ./microservice-chart \
  --namespace default \
  --create-namespace \
  --set environment=dev \
  --set awsAccountId=123456789012 \
  --set hostname=sample-service \
  --set domain=example.com \
  --set image.registry=123456789012.dkr.ecr.eu-central-1.amazonaws.com/sample-service \
  --set image.tag=v1.0.0
```

For repeatable deploys, prefer a values file:

```bash
helm upgrade --install sample-service ./microservice-chart \
  -f values-dev.yaml \
  --set image.tag=$CI_COMMIT_SHA
```

## Values reference

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `environment` | yes | — | Environment name (dev/stage/prod) — used in labels and IRSA role |
| `awsAccountId` | when IRSA enabled | — | AWS account hosting the IRSA role |
| `hostname` | for routing | — | Subdomain part of the URL |
| `domain` | for routing | — | Domain part of the URL |
| `app.name` | yes | `sample-service` | Logical service name |
| `app.selector` | yes | `sample-service` | Pod selector label value |
| `app.fullname` | yes | `sample-service` | `app:` label on pods |
| `app.port` | yes | `8080` | Container port |
| `image.registry` | yes | — | Registry path without tag |
| `image.tag` | yes | `latest` | Image tag (set per deploy) |
| `image.pullPolicy` | no | `IfNotPresent` | |
| `replicaCount` | no | `1` | |
| `resources` | no | `100m/128Mi` requests | |
| `routing.httpRoute.enabled` | no | `true` | Use Gateway API HTTPRoute |
| `routing.httpRoute.parentGateway` | no | `platform-gateway`/`istio-ingress` | Gateway parentRef |
| `routing.ingress.enabled` | no | `false` | Use legacy Ingress instead |
| `serviceAccount.create` | no | `true` | |
| `serviceAccount.irsa.enabled` | no | `false` | Add IRSA annotation |
| `serviceAccount.irsa.roleSuffix` | when IRSA enabled | — | Suffix for the role name |
| `vault.enabled` | no | `false` | Mount Vault secrets via CSI |
| `vault.role` | when Vault enabled | — | Vault role name |
| `vault.address` | no | `http://vault.vault.svc.cluster.local:8200` | |
| `metrics.enabled` | no | `false` | Create ServiceMonitor |
| `metrics.path` | no | `/metrics` | |
| `probes.{readiness,liveness,startup}.enabled` | no | `false` | |
| `hostAliases` | no | `[]` | Pod-level /etc/hosts entries |
| `hostAliasesByEnv` | no | `{}` | Per-environment hostAliases (used when top-level is unset) |
| `extraEnv` | no | `[]` | Extra env vars |

## Routing — Gateway API vs Ingress

The chart defaults to **HTTPRoute** (Gateway API). This pairs with the
`0650-istio-gateway` Terraform module which provisions a `Gateway` named
`platform-gateway` in the `istio-ingress` namespace.

For services still on ingress-nginx (e.g., during migration), set:

```yaml
routing:
  httpRoute:
    enabled: false
  ingress:
    enabled: true
    className: nginx
```

Both paths use external-dns to publish DNS records derived from `${hostname}.${domain}`.

## IRSA pattern

When `serviceAccount.irsa.enabled=true`, the chart constructs the role ARN as:

```
arn:aws:iam::${awsAccountId}:role/${environment}-${serviceAccount.irsa.roleSuffix}
```

The Terraform module that creates the role (e.g., `0410-messaging` for an SQS
consumer) uses the same naming pattern, so they line up by convention.

## Verify locally

```bash
helm lint ./microservice-chart

# Render with sample values
helm template sample-service ./microservice-chart \
  --set environment=dev \
  --set awsAccountId=123456789012 \
  --set hostname=sample \
  --set domain=example.com \
  --set image.registry=registry.example.com/sample \
  --set image.tag=v1
```
