# Runbooks

Common operational tasks. Each entry: when to use, prerequisites, steps,
verification, rollback.

> _Entries marked ✅ were exercised against real operations during validation;
> entries marked "Documented" are procedures grounded in the shipped modules but
> not yet run under a real incident._

## Index

| Task | Status |
|------|--------|
| [Deploy a new microservice](#deploy-a-new-microservice) | ✅ |
| [Migrate a service from ingress-nginx to Gateway API (dual-run)](#migrate-a-service-from-ingress-nginx-to-gateway-api-dual-run) | ✅ |
| [Scale a node group](#scale-a-node-group) | Documented |
| [Rotate an IRSA role](#rotate-an-irsa-role) | Documented |
| [Debug Gateway API routing](#debug-gateway-api-routing) | Documented |
| [Recover from failed Helm release](#recover-from-failed-helm-release) | ✅ |
| [Add a new module](#add-a-new-module) | ✅ |
| [Rotate database password](#rotate-database-password) | Documented |
| [Restore from RDS snapshot](#restore-from-rds-snapshot) | Documented |

---

## Deploy a new microservice

> ✅ _Validated: a real code change was driven through this exact path to a live
> cluster during the CI/CD validation pass._

**When**: adding a service to the monorepo and shipping it to a cluster.

**Prereqs**:
- Service code under `examples/<name>/` (or your own services root) with a
  `Dockerfile` and a `helm-values.yaml` for `helm/microservice-chart`.
- Platform stack applied: EKS, cert-manager, Istio + the `platform-gateway`
  Gateway, and (for CI deploys) the `0710-cicd-oidc` deploy role.
- A per-service IRSA role for any AWS access the service needs — see the
  `examples/sample-services` Terraform for the producer/consumer pattern.

**Steps**:
1. **Add a trigger** to the root `ci/gitlab-ci/.gitlab-ci.yml` (copy an existing
   `trigger-*` block). The monorepo dispatches a per-service child pipeline.
2. **Add `examples/<name>/.gitlab-ci.yml`** extending the base templates
   (`env-config`, `base-build`, `base-deploy`, `base-rollback`). Set
   `SERVICE_NAME`, `BUILD_CONTEXT`, `HELM_VALUES`, and any `EXTRA_HELM_ARGS`
   (e.g. `--set extraEnv.SQS_QUEUE_URL=$SAMPLE_QUEUE_URL`). Use
   `examples/sample-producer/.gitlab-ci.yml` as the template.
3. **Wire IRSA** in `helm-values.yaml`: `serviceAccount.name` must equal the
   IRSA role's trust subject, and the role ARN is supplied at deploy time
   (`--set serviceAccount.roleArn=<arn>`). The chart attaches an `HTTPRoute` to
   `platform-gateway` by default — set `routing.httpRoute.pathPrefix`.
4. **Push.** The pipeline authenticates to AWS via OIDC (no stored keys),
   builds for the **node architecture** (the reference nodes are ARM64, so the
   build cross-compiles with buildx), pushes to ECR, and runs `helm upgrade`.

**Verify**:
```bash
kubectl get pods -n <name>                  # Running, correct arch
kubectl get httproute -n <name>             # Accepted=True, ResolvedRefs=True
kubectl describe sa <name> -n <name>        # eks.amazonaws.com/role-arn annotation present
curl -H 'Host: <svc-host>' http://<gateway-lb>/<prefix>/   # end-to-end 200
```

**Gotchas learned in validation**:
- Build for the node arch — amd64 images crash-loop on ARM64 nodes.
- The IRSA role ARN must render as a **string**; passing the account id as an
  int via `--set` produced a malformed ARN and silently broke AWS access (the
  pod ran, health checks passed, but it couldn't reach SQS).
- A restricted cluster API endpoint blocks hosted CI runners — run the runner
  in-VPC against the private endpoint, or allow the runner's IP range.

**Rollback**: see [Recover from failed Helm release](#recover-from-failed-helm-release),
or re-run the pipeline's `rollback` job with `ROLLBACK_TAG=<previous-tag>`.

---

## Add a new module

**Prereqs**: clear understanding of what category the new module belongs to.

**Steps**:
1. Pick the smallest unused [XXYZ number](decisions/ADR-006-xxyz-numbering.md)
   in the right category.
2. Create `terraform/environments/<env>/<XXYZ>-<name>/` with `main.tf`,
   `variables.tf`, `outputs.tf`, `terraform.tfvars.example`, `backend.tf`.
3. Match the existing module shape: provider block with `dynamic "assume_role"`
   and `default_tags`, standard variables (`assume_role_arn`, `tags`).
4. Run `./scripts/validate.sh` locally.
5. PR. CI runs plan, comments on PR. Merge to apply.

**Verification**: module's resources show in AWS console with expected tags.

---

## Scale a node group

> _Documented procedure; capacity bounds change in Terraform, day-to-day scaling
> is delegated to the autoscaler. Not load-tested in the PoC._

**Manual (change capacity bounds)**: edit `min_size` / `max_size` /
`desired_size` for the managed node group in `0210-eks` (module input or
`terraform.tfvars`), then `terraform apply` the `0210-eks` root. The node group
updates in place; new nodes join in a few minutes.

**Automatic (recommended)**: apply `0220-eks-cluster-autoscaler`. It watches for
`Pending` pods that can't schedule, grows the node group up to `max_size`, and
scales back in when nodes are underutilized. Tune via that module's tfvars
(`scale-down-utilization-threshold`, `scale-down-unneeded-time`). Keep
`desired_size` modest and let the autoscaler converge — don't pin a hardcoded
`desired_size` that you re-assert on every apply.

**Verify**:
```bash
kubectl get nodes -L node.kubernetes.io/instance-type
kubectl -n kube-system logs deploy/cluster-autoscaler | tail
kubectl get events -A | grep -iE 'TriggeredScaleUp|ScaleDown'
```

**Gotcha**: a `Pending` pod that can't fit on *any* instance type in the group
(requests too large, or a `WaitForFirstConsumer` PVC bound to a zone with no
node) will **not** trigger a scale-up. Check the pod's events before assuming
the autoscaler is broken.

---

## Rotate an IRSA role

> _Documented procedure. Grounded in the IRSA pattern validated end-to-end
> (the `examples/sample-services` producer/consumer roles)._

An IRSA role's trust policy federates the cluster's EKS OIDC provider to a
specific subject `system:serviceaccount:<namespace>:<serviceaccount>`. The pod's
ServiceAccount carries an `eks.amazonaws.com/role-arn` annotation; the EKS
webhook injects a projected token and `AWS_ROLE_ARN`, and the SDK calls STS
`AssumeRoleWithWebIdentity` on its own.

**Change a role's permissions** (most common):
1. Edit the policy in the owning Terraform (the service's IRSA module, e.g.
   `examples/sample-services`), then `terraform apply` that root.
2. The change takes effect on the next STS credential refresh (token TTL,
   typically ≤ 1h) — no redeploy needed. Restart the pod to pick it up now.

**Point a service at a different role**:
1. Set `serviceAccount.roleArn` in the service's `helm-values.yaml` (or
   `--set serviceAccount.roleArn=<arn>`), redeploy.
2. Restart pods so the webhook re-injects the new `AWS_ROLE_ARN`.

**Rename the ServiceAccount** (changes the trust subject — do both halves
together or you'll get runtime `AccessDenied`):
1. Update the role's trust condition to the new subject
   (`...:sub = system:serviceaccount:<ns>:<new-sa>`).
2. Update the chart's `serviceAccount.name` to match, apply + redeploy.

**Verify**:
```bash
kubectl describe sa <sa> -n <ns> | grep role-arn         # annotation present
kubectl exec <pod> -n <ns> -- env | grep AWS_ROLE_ARN
kubectl exec <pod> -n <ns> -- aws sts get-caller-identity # assumed-role/<role>/...
```

**Gotchas learned in validation**:
- The role ARN annotation must be a valid **string** ARN. An account id rendered
  as an int produced a malformed ARN and the assume silently failed — the pod
  ran fine (health checks need no AWS) but every AWS call was denied.
- The SA name in the trust subject must **exactly** match the chart's SA. A
  mismatch surfaces only at runtime, as `AccessDenied`, not at deploy time.

---

## Debug Gateway API routing

> _Documented procedure. The happy path (Gateway + HTTPRoute → live traffic) was
> validated end-to-end; this is the layered checklist when it isn't working._

Work outward from the gateway to the pod:

1. **Is the Gateway programmed?**
   ```bash
   kubectl get gateway -n istio-ingress           # PROGRAMMED=True, ADDRESS set
   kubectl get svc -n istio-ingress               # auto-provisioned LB Service exists
   ```
2. **Is the route attached?**
   ```bash
   kubectl get httproute -A
   kubectl describe httproute <name> -n <namespace>   # Accepted=True, ResolvedRefs=True
   ```
   Common causes of `Accepted=False` / `ResolvedRefs=False`: `parentRefs`
   name/namespace not matching `platform-gateway`/`istio-ingress`; backend
   Service missing or wrong port; an empty hostname producing an invalid
   `hostnames` entry.
3. **Is the backend healthy?**
   ```bash
   kubectl get endpoints <svc> -n <namespace>     # non-empty
   kubectl get pods -n <namespace>                # Ready
   ```
4. **What does Envoy actually see?**
   ```bash
   istioctl proxy-config routes <gateway-pod>.istio-ingress
   istioctl proxy-config clusters <gateway-pod>.istio-ingress | grep <svc>
   ```
5. **Path handling.** The chart's HTTPRoute strips its `pathPrefix` before the
   backend (a URLRewrite). A 404 *at the app* usually means the backend didn't
   expect the prefix, or the rewrite is misconfigured.

**Gotchas learned in validation**: an empty host produced an invalid
`hostnames: "."`; an early chart version never stripped the path prefix before
the backend; and a `ServiceMonitor` selector that matched no Service broke
scraping (not routing, but it surfaces in the same debugging session).

---

## Recover from failed Helm release

> ✅ _Validated: `helm history` / `rollback` / `uninstall` were exercised during
> the PoC and teardown._

**When**: a `helm upgrade` left a release `failed` or stuck `pending-upgrade`,
or a bad deploy needs reverting.

**Steps**:
1. Inspect history and find the last good revision:
   ```bash
   helm history <release> -n <namespace>
   ```
2. Roll back:
   ```bash
   helm rollback <release> <revision> -n <namespace> --wait --timeout 5m
   ```
3. If the release is stuck `pending-*` (a previous command was interrupted),
   roll back to the last *deployed* revision — Helm clears the lock.
4. If state is unrecoverable, uninstall keeping history, then redeploy clean:
   ```bash
   helm uninstall <release> -n <namespace> --keep-history
   # then re-run the deploy pipeline (or helm upgrade --install)
   ```

**Verify**:
```bash
helm status <release> -n <namespace>            # STATUS: deployed
kubectl rollout status deploy/<release> -n <namespace>
```

**Gotchas learned in validation**:
- **Don't mix manual `kubectl` edits with Terraform-managed Helm releases.** A
  manually-resized PVC made a later `terraform apply` fail
  (`storage … can not be less than status.capacity`). Stay all-Terraform or
  all-manual within a sequence.
- **Deleting a PVC backing a Deployment hangs** on the `pvc-protection`
  finalizer because the Deployment respawns a pod that mounts it. Scale the
  Deployment to 0 first, then delete the PVC.

---

## Rotate database password

> _Documented procedure. SSM Parameter Store is the source of truth for the DB
> password._

The RDS module (`0320-rds`) reads its master password from an SSM `SecureString`
at `/platform/<env>/0320-rds/db_password`; the prod Aurora module (`0330-aurora`)
uses `/platform/prod/0330-aurora/master_password` (and `/…/app_passwords`).
The instance's `password` is sourced from that SSM parameter, so SSM drives it.

**Steps**:
1. Write the new value:
   ```bash
   aws ssm put-parameter --name /platform/<env>/0320-rds/db_password \
     --type SecureString --value '<new-password>' --overwrite
   ```
2. `terraform apply` the `0320-rds` (or `0330-aurora`) root. The apply reads the
   new SSM value and issues the `ModifyDB*` master-password change. RDS applies a
   master-password change immediately (it's not deferred to the maintenance
   window).
3. Roll any workload that cached the old password (restart pods / refresh the
   mounted secret). With Vault dynamic credentials this step is unnecessary.

**Verify** (from the bastion):
```bash
psql "host=<rds-endpoint> user=platform_admin dbname=postgres" -c 'select 1;'
```

**Gotcha**: don't change the password out-of-band in the console — it will drift
from SSM, and the next `terraform apply` will reset it to the SSM value. Always
rotate through SSM.

---

## Restore from RDS snapshot

> _Documented procedure. RDS/Aurora restores create a **new** instance — there is
> no in-place restore._

**Steps**:
1. Find the snapshot:
   ```bash
   aws rds describe-db-snapshots --db-instance-identifier rds-<env> \
     --query 'reverse(sort_by(DBSnapshots,&SnapshotCreateTime))[].[DBSnapshotIdentifier,SnapshotCreateTime]' \
     --output table
   ```
   (The final snapshot, if `skip_final_snapshot = false`, is `rds-<env>-final`.)
2. Restore to a new identifier, reusing the existing subnet group + SG:
   ```bash
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier rds-<env>-restore \
     --db-snapshot-identifier <snapshot-id> \
     --db-subnet-group-name rds-<env> \
     --vpc-security-group-ids <rds-sg-id>
   ```
3. Validate data on the restored instance before any cutover.
4. **Cut over the clean way**: bring the restored instance under Terraform —
   point the `0320-rds` module at the new identifier (or `terraform import` it),
   update apps to the new endpoint, then retire the old instance. Avoid
   hand-managing the restored instance long-term.

**Gotchas**:
- A restored instance comes up with a **new endpoint** and, unless overridden,
  default parameter/option groups and the snapshot's security group — re-assert
  your SG, subnet group, and parameter group.
- Its password is whatever it was **at snapshot time**; reset it via the
  [Rotate database password](#rotate-database-password) procedure.
- Deletion protection / final-snapshot settings from the module don't carry to a
  CLI-restored instance — set them before it's load-bearing.

---

## Migrate a service from ingress-nginx to Gateway API (dual-run)

> ✅ _Validated: this exact per-service procedure was run to move live services
> from ingress-nginx to the Istio Gateway API on production clusters, one host at
> a time, with rollback always available. See ADR-003 → "Validated in production"._

**When**: moving an existing service off ingress-nginx onto the Istio Gateway
API without downtime, while other services stay on nginx.

**Principle**: **dual-run.** The HTTPRoute is added *alongside* the live Ingress;
both exist. The cut is a per-host DNS repoint (nginx LB → gateway LB). Rollback is
repointing DNS back. nginx is left untouched until the whole environment is
migrated.

**Prereqs**:
- Platform layer present on the target cluster: Istio + the `platform-gateway`
  Gateway, and the AWS Load Balancer Controller (gateways on an NLB).
- The gateway's NLB `:443` listener terminates TLS with the **same** cert the
  nginx LB uses (e.g. an ACM wildcard covering the host) → no cert regression.
- The chart's `httproute.yaml` is CRD-capability-gated, so `httpRoute.enabled=true`
  is safe to promote even to clusters not yet migrated.

**Steps**:
1. **Baseline.** Record the service's current nginx Ingress host → backend
   `svc:port`, and confirm `https://<host>/<healthpath>` returns its normal code.
2. **Enable dual-run.** In the service's values, set **both**
   `routing.httpRoute.enabled: true` and `routing.ingress.enabled: true`, then
   `helm upgrade --install`. The HTTPRoute is created; the Ingress stays live.
3. **Verify the gateway path BEFORE touching DNS.** Curl the gateway LB directly
   with the real Host header (`curl --resolve <host>:443:<gateway-lb-ip> https://<host>/<healthpath>`).
   Expect the app response, not a 404 — this proves routing without moving traffic.
4. **Cut DNS.** Repoint the host's record from the nginx LB to the gateway LB
   (lower the TTL first, e.g. 300→60s). Validate against a **public resolver or
   the gateway LB directly**, not a possibly-cached local resolver.
5. **Monitor** at least one TTL window on real traffic.
6. **Leave the nginx Ingress in place** until the whole environment is migrated
   (it is your rollback path — see the note below).

**Verification**:
- HTTPRoute `Accepted=True` and `ResolvedRefs=True`; Gateway `Programmed=True`.
- `openssl s_client -connect <gateway-lb>:443` handshake returns `Verify return code: 0`.
- The resolved target for `<host>` is the gateway LB, and the app answers end-to-end.
- ⚠️ A cert check alone does **not** prove you hit the gateway — if TLS terminates
  with the same ACM cert on both LBs, the issuer is identical. Check the resolved
  target/IP.

**Rollback**: repoint the host's DNS record back to the nginx LB. Because dual-run
kept the Ingress live, this is instantaneous — no redeploy.

**Behavioral parity — audit before cutting.** Routing working is not behavioral
parity. Custom nginx annotations do **not** transfer to the HTTPRoute automatically.
Before cutting a service, check per-service (timeouts, body size, buffer sizes,
websocket) and controller-level nginx config, and decide each disposition. Note
Envoy imposes no request timeout by default (looser than nginx, not tighter) — set
an HTTPRoute `timeouts.request` for parity and a runaway ceiling if you relied on
nginx's.

**"Migrated" is not "retired".** Under a shared-values promotion model, do **not**
follow up by setting `ingress.enabled: false` to remove nginx from a single
environment — that value promotes to environments with no gateway and black-holes
them. Hold the dual-config until every environment has the gateway (or make
`ingress.enabled` per-environment). See ADR-003.
