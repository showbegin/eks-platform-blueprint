# Runbooks

Common operational tasks. Each entry: when to use, prerequisites, steps,
verification, rollback.

> _Most entries are skeletons until the Phase 6 PoC produces real failure
> recoveries. Filled-in entries marked ✅._

## Index

| Task | Status |
|------|--------|
| [Deploy a new microservice](#deploy-a-new-microservice) | ✅ |
| [Scale a node group](#scale-a-node-group) | Skeleton |
| [Rotate an IRSA role](#rotate-an-irsa-role) | Skeleton |
| [Debug Gateway API routing](#debug-gateway-api-routing) | Skeleton |
| [Recover from failed Helm release](#recover-from-failed-helm-release) | Skeleton |
| [Add a new module](#add-a-new-module) | ✅ |
| [Rotate database password](#rotate-database-password) | Skeleton |
| [Restore from RDS snapshot](#restore-from-rds-snapshot) | Skeleton |

---

## Deploy a new microservice

**Prereqs**: Service code in `services/<name>/` with Dockerfile and
`helm-values.yaml`. Cluster has Istio Gateway and cert-manager installed.

**Steps**:
1. Add a trigger block to the GitLab CI root pipeline (see
   `ci/gitlab-ci/.gitlab-ci.yml` for shape — copy any existing block).
2. Create `services/<name>/.gitlab-ci.yml` extending `.base_build` and
   `.base_deploy` (see `ci/gitlab-ci/example-service-ci.yml`).
3. Push to the `dev` branch. The pipeline builds, pushes to ECR, and runs
   `helm upgrade`.
4. Verify: `kubectl get httproute -n <name>`, `kubectl get svc -n <name>`.

**Rollback**: re-run the pipeline with `ROLLBACK_TAG=<previous-tag>` (see
`ci/gitlab-ci/templates/base-deploy.yml`).

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

> _Skeleton — to be filled after Phase 6 PoC scaling tests._

**Manual**: edit `min_size`/`max_size` in `0210-eks/main.tf`, apply.

**Automatic**: cluster-autoscaler (`0220-eks-cluster-autoscaler`) handles scale
based on pending pods. Configure thresholds via
`terraform/environments/<env>/0220-eks-cluster-autoscaler/terraform.tfvars`.

---

## Rotate an IRSA role

> _Skeleton — fill after PoC validates the IRSA pattern end-to-end._

The role's trust policy references the OIDC subject `system:serviceaccount:<ns>:<sa>`.
Renaming requires updating the policy and rotating the ServiceAccount annotation.

---

## Debug Gateway API routing

> _Skeleton — most-likely-to-be-fleshed-out runbook after migration._

Quick checks:

```bash
kubectl get gateway -n istio-ingress
kubectl get httproute -A
kubectl describe httproute <name> -n <namespace>
istioctl proxy-config routes <gateway-pod>
```

---

## Recover from failed Helm release

> _Skeleton._

```bash
helm history <release> -n <namespace>
helm rollback <release> <revision> -n <namespace>
```

If state is corrupted: `helm uninstall <release> --keep-history` then redeploy.

---

## Rotate database password

> _Skeleton — RDS module uses SSM Parameter Store for password._

```bash
aws ssm put-parameter --name /<env>/rds/password --value <new> --type SecureString --overwrite
```
Then trigger a redeploy of any service that reads it (Vault refresh or pod restart).

---

## Restore from RDS snapshot

> _Skeleton._

Restore creates a new instance from snapshot. Update the Terraform module to
point at the new identifier and re-apply.
