# Migrating to this blueprint

> **Status**: skeleton. The full migration story will be documented in a companion
> repo (`k8s-ops`) and summarized here after a real ingress-nginx → Gateway API
> migration is completed against a production-shaped staging cluster.
>
> Expected publication: Post 2 in the LinkedIn series.

## Migration scenarios

### From ingress-nginx to Istio + Gateway API

The most common migration target for this blueprint. ingress-nginx is in
maintenance mode (see [ADR-003](decisions/ADR-003-gateway-api-over-ingress.md));
Gateway API is the successor.

**High-level steps** (to be expanded with concrete commands and gotchas):

1. **Inventory existing Ingresses** — `kubectl get ingress -A -o yaml > existing-ingresses.yaml`. Capture every annotation, rewrite, auth, and TLS config.
2. **Install Istio + Gateway API CRDs alongside ingress-nginx** — both can run; route traffic via DNS, not by replacing the LB.
3. **Translate Ingress to HTTPRoute, one service at a time** — see translation table below.
4. **Test with a canary subdomain** — `<service>.gw.<env>.<domain>` points at the Istio gateway while `<service>.<env>.<domain>` still routes via ingress-nginx.
5. **Cut over DNS** — switch the production hostname to the Istio NLB.
6. **Remove ingress-nginx after the soak period** — typically 2 weeks.

### Annotation → HTTPRoute translation table

> _To be filled with concrete examples after migration._

| ingress-nginx annotation | Gateway API equivalent |
|-------------------------|------------------------|
| `nginx.ingress.kubernetes.io/rewrite-target` | `URLRewrite` filter |
| `nginx.ingress.kubernetes.io/ssl-redirect` | Gateway listener config |
| `nginx.ingress.kubernetes.io/auth-url` | `ExtensionRef` to AuthorizationPolicy |
| `nginx.ingress.kubernetes.io/proxy-body-size` | Istio `EnvoyFilter` |
| `nginx.ingress.kubernetes.io/canary` | `HTTPRoute` weighted backendRefs |

### Common gotchas

> _To be expanded based on real migration findings:_
> - Wildcard hostnames in HTTPRoute vs Ingress
> - Namespace boundaries with `ReferenceGrant`
> - Path matching subtleties (Prefix vs Exact)
> - cert-manager: HTTP-01 challenge through Gateway requires `gateway-shim`

## From bare AWS to this blueprint

If you're starting from raw AWS resources (no IaC), consider:

1. **Import what you have**: `terraform import` for the existing VPC, EKS cluster, RDS.
2. **Wrap with this blueprint's modules** for everything new.
3. **Slowly replace** existing resources with module-managed ones during scheduled changes.

Don't rewrite everything in one PR. Migration is episodic, not a single cutover.

## From a tutorial-style single-root-per-env structure

If your existing Terraform is a single `main.tf` per env that calls many
modules, the migration to per-module roots (this blueprint's pattern) is:

1. **Create the new structure** — `terraform/environments/<env>/<XXYZ>-<name>/` per module.
2. **Move state in chunks** — `terraform state mv` from old to new.
3. **One module at a time** — apply each new root, verify no drift, move on.

See [ADR-010](decisions/ADR-010-per-module-roots.md) for the rationale.

## Companion repo

Live migration commits, scripts, and post-mortem will be in
`github.com/showbegin/k8s-ops` (companion repo). This file links there once published.
