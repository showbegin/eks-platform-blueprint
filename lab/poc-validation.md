# PoC Validation Log

A from-scratch validation of this blueprint on a fresh single-account EKS
cluster. The goal: stand the platform up end-to-end exactly as documented, find
where reality diverges from the README, and fix it.

> This is a real validation run, not a synthetic demo. Account IDs, IP CIDRs,
> load-balancer hostnames, and credentials have been redacted with placeholders.

## Environment

| Item | Value |
|---|---|
| Mode | Single AWS account (no cross-account assume-role) |
| Region | `eu-central-1` |
| Kubernetes | 1.35 |
| Nodes | 2x `m6g.xlarge` Bottlerocket (arm64) |
| Apply order | state-backend -> 0110-vpc -> 0210-eks -> addons -> operator stack |

## What came up clean

- **VPC + EKS control plane + managed node group** - Bottlerocket arm64 nodes
  Ready, control-plane logging on.
- **Managed addons** (vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver) - all
  `ACTIVE` once the ordering fix (below) was in place.
- **cert-manager** - 3 pods Running, self-signed `ClusterIssuer` Ready.
- **Istio** (base + istiod + ingress gateway) - all `deployed`, gateway LB
  provisioned.
- **kube-prometheus-stack** - Prometheus (21/21 targets up), Grafana
  (`/api/health` ok), Alertmanager, node exporters all Running.
- **Workload smoke test** - a sample service deployed via
  `helm/microservice-chart`, reachable end-to-end through the gateway returning
  HTTP 200, with the request path confirmed in the Envoy headers.

## Version-currency policy

Every tool is pinned to its **latest stable** release as validated here, and
kept current as a maintenance practice. Stale pins are how you ship a repo that
fails on someone else's cluster on day one (see Finding 4 below - an old chart
pin that is simply broken).

| Component | Validated version |
|---|---|
| Kubernetes | 1.35 |
| vpc-cni | `v1.22.1-eksbuild.2` |
| kube-proxy | `v1.35.3-eksbuild.11` |
| coredns | `v1.14.3-eksbuild.2` |
| aws-ebs-csi-driver | `v1.60.1-eksbuild.1` |
| cert-manager | `v1.20.2` |
| Istio (base/istiod/gateway) | `1.30.0` |
| kube-prometheus-stack | `86.1.0` |
| Gateway API CRDs | `v1.5.1` |

## Findings

Issues found by actually running the thing. The ones that block a fresh
`apply` of the documented quickstart are marked **blocks quickstart**.

### Finding 1 - Single-account mode required an access-entry fix · blocks quickstart

In single-account mode (no cross-account role), the cluster access-entry
principal resolved to `null` and the apply failed. Fixed by coalescing the
principal ARN to the caller identity when no assume-role is configured.

### Finding 2 - Addon ordering deadlock · blocks quickstart

`vpc-cni` must install **before** the node group joins (`before_compute`), and
the addon conflict-resolution fields must be set for both create and update.
Without this, nodes can come up without a working CNI and the addons wedge.
Fixed in the EKS module addon block.

### Finding 3 - cert-manager `ClusterIssuer` fails at plan time · blocks quickstart

The `ClusterIssuer` was declared with `kubernetes_manifest`, which validates the
resource against the cluster API **at plan time**. On a fresh cluster the
`cert-manager.io` CRDs don't exist yet (the Helm release that installs them runs
in the same plan), so `terraform plan` fails with "API did not recognize
GroupVersionKind".

**Fix in repo (implemented)**: the ClusterIssuer manifests in `0610-cert-manager`
now use `kubectl_manifest` from the `gavinbunney/kubectl` provider, which
defers validation to apply time. The `hashicorp/kubernetes` provider is no
longer required for this module, and the chart-then-CR ordering inside one
plan works on a fresh cluster without any `-target` workaround. The Helm
release remains the dependency anchor (`depends_on = [helm_release.cert_manager]`).

### Finding 4 - Istio gateway chart 1.24.x has a broken values schema · blocks quickstart (at old pin)

The Istio `gateway` chart versions 1.24.0-1.24.6 ship a `values.schema.json`
that rejects the chart's own default values (the internal
`_internal_defaults_do_not_set` key, plus standard keys like `service`,
`autoscaling`, `resources`). Any user-supplied values trigger:

```
values don't meet the specifications of the schema(s):
  additional properties '...' not allowed
```

This is an upstream chart bug, reproducible with `helm install --dry-run` using
the chart's own defaults; `--disable-openapi-validation` does not bypass it.
**Fix**: pin to a known-good version. This blueprint uses `1.30.0`.

### Finding 5 - No working default StorageClass on EKS 1.35 · blocks quickstart (any PVC workload)

EKS ships a `gp2` StorageClass annotated as default, but its provisioner is the
**in-tree** `kubernetes.io/aws-ebs` driver - deprecated in K8s 1.27 and removed
in 1.31. The class exists but cannot provision volumes. The blueprint installs
the EBS CSI driver but never created a CSI-backed StorageClass. Result: any PVC
(Prometheus, Grafana, Alertmanager, or any user workload) hangs `Pending`
forever with no obvious error.

**Fix in repo (implemented)**: `0210-eks/main.tf` now creates a `gp3`
`StorageClass` backed by `ebs.csi.aws.com`, encrypted, `WaitForFirstConsumer`,
allow-volume-expansion, marked default, after the cluster module is up. It
also clears the legacy `gp2` class's `is-default-class` annotation (via
`kubernetes_annotations` with `force = true`), so workloads don't see two
defaults. The StorageClass lives in the same module as the EBS CSI addon and
its IRSA role, since they're a single consumable unit.

### Finding 6 - Workload chart expects Gateway API, platform never installs it · blocks quickstart (any chart workload)

`helm/microservice-chart` defaults to emitting a Gateway API `HTTPRoute`
attached to a `Gateway` named `platform-gateway` in `istio-ingress`. But the
platform as shipped provides neither:

- **No Gateway API CRDs** are installed - the `HTTPRoute` kind doesn't exist, so
  the chart's resource can't even be created.
- **No `platform-gateway` Gateway** exists - the istio-gateway module installs
  the *legacy* Istio ingress gateway (a Deployment + LoadBalancer Service), not
  a Gateway API `Gateway`. `HTTPRoute`s can't attach to it.

The platform layer speaks "legacy Istio ingress"; the workload chart speaks
"modern Gateway API". They were never reconciled.

**Validated fix path** (what this run did to prove it works):

1. Install the Gateway API standard CRDs (pinned, version-coupled to Istio).
   Istio auto-registers the `istio` GatewayClass the moment they exist.
2. Create the `platform-gateway` Gateway (`gatewayClassName: istio`). Istio's
   deployment controller auto-provisions the gateway Deployment + LB.
3. Deploy a service via the chart with default routing -> `HTTPRoute` reports
   `Accepted=True`, `ResolvedRefs=True`.
4. `curl -H 'Host: <svc-host>' http://<gateway-lb>/` -> **HTTP 200**, request
   routed gateway -> service -> pod.

**Fix in repo (implemented)**: the structural fix is now in the modules. A new
`0600-gateway-api-crds` module installs the upstream Gateway API standard CRDs
at a pinned version (currently `v1.5.1`) before istiod runs. Modules
`0650-istio-gateway` and `0660-istio-gateway-internal` no longer install the
legacy Helm chart — they create Gateway API `Gateway` resources named
`platform-gateway` (external) and `platform-gateway-internal` (internal) in the
`istio-ingress` namespace, both with `gatewayClassName: istio`. Istio's
deployment controller auto-provisions the Envoy data plane and the LoadBalancer
Service for each. ACM TLS termination at the AWS classic LB is wired through
`spec.infrastructure.annotations` on the Gateway resource, which Istio copies
onto the auto-provisioned Service. The microservice chart's HTTPRoute defaults
attach to `platform-gateway` exactly as written — no changes needed on the
workload side. End-to-end pass through this exact pattern was validated live
during the PoC, and again on the CI/CD validation pass (a CI-built image,
deployed via the chart, reachable end-to-end through the gateway).

### Finding 7 - Upstream module pins drift

`terraform-aws-modules` pins lag current releases, and two IRSA submodule
references were missing version pins entirely (added). Major-version bumps (VPC
5->6) carry breaking changes and are tracked as a separate, tested migration.

## Operational notes worth keeping

- **Mixing manual `kubectl` ops with Terraform-managed Helm releases causes
  drift.** A manually-recreated PVC at a non-default size made a later
  `terraform apply` fail (`spec.resources.requests.storage: Forbidden: field
  can not be less than status.capacity`). Stay all-Terraform or all-manual
  within a sequence; don't mix mid-stream.
- **Deleting a PVC backing a Deployment hangs** on the `pvc-protection`
  finalizer because the Deployment immediately respawns a pod that mounts it.
  Scale the Deployment to 0 first, then delete the PVC.
- **Don't `pkill -f 'terraform apply'` from a wrapper shell** - the pattern
  matches the wrapper's own command line and SIGTERMs the wrong process. Look up
  the PID with `pgrep` and kill that.

## Cost discipline

Validation ran on right-sized infra (2 nodes, small EBS, single NAT) with a
budget alarm in place, and was torn down the same day. A from-scratch
stand-up -> validate -> destroy cycle is cheap when the destroy actually happens.


## CI/CD pipeline validation (second pass)

The first pass validated the infrastructure (apply -> workload -> destroy). The
second pass validated the part reference repos rarely test: a real code change
flowing through the pipeline to the live cluster, with no human in the loop. A
private GitLab project was wired to the cluster account via OIDC, a commit was
pushed, and the build->deploy was observed end to end. This surfaced a further
set of findings, summarized below.

### The workload chart was not deployable as shipped

Seven defects only appear on a real `helm install`, not on `helm template`:
`extraEnv` was ranged over as a list but documented as a map; the ServiceAccount
name didn't match the IRSA trust subject; an empty host produced an invalid
`hostnames: "."`; the route never stripped its path prefix before the backend;
the ServiceMonitor selector matched no Service. Each is small; together the demo
app could not run or be scraped. All fixed in the chart.

### The CI/CD was wired to a layout that didn't ship

The pipeline targeted a `services/` tree the repo doesn't include, never wired
IRSA into the deploy step, and the build wasn't architecture-aware (amd64 images
would crash-loop on the ARM64 nodes). Rewired: OIDC-based AWS auth, IRSA wired
via the chart's computed role path, and a cross-compiling buildx build that
targets the node architecture.

### Bugs only a real runner finds

- **Runner-to-cluster reachability.** OIDC auth and ECR push succeeded, then
  `helm` timed out: the cluster API endpoint was restricted to a single IP and
  the hosted runners aren't that IP. This is a real architecture decision, now
  documented: run the CI runner in-VPC against the private endpoint, or open the
  public endpoint to the runner range (it remains IAM/access-entry authenticated).
- **A module that breaks its own re-apply.** In-cluster Kubernetes resources were
  managed by a provider whose host came from a data source of the very cluster
  being modified, so on update the provider resolved to `localhost`. Lesson:
  don't mutate a cluster and manage its in-cluster objects in the same module.
- **A malformed IRSA annotation from a type coercion.** Passing the account id
  via `--set` typed it as an integer, and the chart's string formatting produced
  a broken role ARN — so IRSA was silently non-functional on the deployed pod
  (it ran, because health checks need no AWS, but it could not reach SQS). Caught
  only by driving real traffic through it. Fixed by coercing to string in the chart.

### Build-environment notes worth keeping

- `docker buildx` needs the dind daemon up before the builder is created; wait
  for `docker info` first.
- With the `docker-container` buildx driver, running dind without TLS on the
  internal CI network avoids a TLS-context error.
- A stale `libexpat` in a `docker:27` Alpine image broke every Python/`aws-cli`
  invocation (`pyexpat` symbol relocation). `apk upgrade` before installing
  `aws-cli` resolves it. Treat base-image package skew as a real, recurring risk.

## AI merge-request review (Bedrock)

An optional, advisory MR/PR review job sends the diff plus the repo's own context
(ADRs, OPA policies, architecture doc) to a Bedrock Claude model and posts a
structured, severity-tagged review as a comment. Validated end to end: a planted
change (a wildcard IAM policy and an open security group) was flagged as
violating the project's own decision records by number, with a BLOCK verdict.

Security properties, by design:
- Keyless: the job assumes a role via OIDC web-identity; no stored AWS keys.
- Least privilege: the review role can do `bedrock:InvokeModel` only - no ECR,
  no EKS, no deploy.
- Fork-safe: fork pipelines can't assume the role (trust is repo-scoped) and
  don't receive a writable token, so they're skipped.
- Advisory: a soft gate by default; opt-in to fail on a high-severity verdict.
- Honest about prompt injection: the diff is attacker-influenceable text, but the
  job takes no actions, so the worst case is a misleading comment.

One script serves both GitHub Actions and GitLab CI, and the grounding paths are
configurable, so the same reviewer drops into an application repo by pointing it
at that repo's standards and adjusting the prompt focus.
