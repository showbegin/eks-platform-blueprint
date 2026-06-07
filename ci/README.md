# CI/CD Architecture

## Why two CI systems?

This isn't preference — it's dependency-graph-forced.

| Concern | Tool | Why |
|---------|------|-----|
| Infrastructure (Terraform) | GitHub Actions | Repo lives on GitHub. OIDC integration is native. Plan-on-PR, apply-on-merge is the standard pattern. |
| Applications (Docker + Helm) | GitLab CI | Monorepo SERVICE-variable dispatch, reusable templates, per-env branch mapping. Works on GitLab.com free tier. |

The split exists because:
1. Infrastructure changes are **gated** (plan → review → apply). GitHub's PR review + environment protection rules handle this natively.
2. Application deploys are **fast** (build → push → helm upgrade). GitLab's child pipeline pattern with SERVICE-variable dispatch handles monorepo routing cleanly.
3. Neither tool does the other's job well. GitHub Actions lacks GitLab's `trigger:` + `include:` child pipeline pattern. GitLab lacks GitHub's OIDC-native AWS integration.

## GitHub Actions — Infrastructure

```
ci/github-actions/
├── terraform-dev.yaml     # PR → plan + comment; merge → apply
└── terraform-prod.yaml    # Same + environment protection (manual approval)
```

### How it works

1. Push to `terraform/environments/dev/**` triggers the dev workflow
2. `detect-changes` job diffs HEAD^ to find which module directories changed
3. Matrix strategy runs `fmt → init → plan → apply` for each changed module
4. On PR: plan output is commented on the PR for review
5. On merge to main: `terraform apply -auto-approve`

### Key patterns

- **OIDC authentication**: no stored AWS credentials. The workflow assumes a role via GitHub's OIDC provider.
- **Matrix from git diff**: only changed modules are planned/applied. No wasted compute.
- **PR comment with plan**: reviewers see exactly what will change before approving.
- **Environment protection** (prod): requires manual approval before apply runs.

### Setup

1. Create OIDC identity provider in AWS IAM (audience: `sts.amazonaws.com`)
2. Create IAM role with trust policy for `repo:showbegin/eks-platform-blueprint:*`
3. Set `AWS_ROLE_ARN_DEV` / `AWS_ROLE_ARN_PROD` as repository variables

## GitLab CI — Applications

```
ci/gitlab-ci/
├── .gitlab-ci.yml              # Root pipeline — SERVICE-variable dispatch
├── templates/
│   ├── env-config.yml          # Branch → account/domain/role mapping
│   ├── base-build.yml          # Docker build + ECR push
│   └── base-deploy.yml         # assume-role + helm upgrade + rollback
└── example-service-ci.yml      # Per-service pipeline example
```

### How it works

1. Push to `services/api/**` on the `dev` branch triggers `trigger-api` job
2. Child pipeline (`services/api/.gitlab-ci.yml`) runs, extending base templates
3. Build: Docker build → tag with `{service}-{branch}-{pipeline_id}` → push to ECR
4. Deploy: exchange GitLab OIDC token for AWS creds → update kubeconfig → helm upgrade

### Key patterns

- **SERVICE-variable dispatch**: set `SERVICE=api` in pipeline variables to force-deploy a specific service without code changes. Essential for rollbacks and hotfixes.
- **Branch = environment**: `dev` branch deploys to dev account, `stage` to stage, `prod` to prod.
- **Single env-config file**: all account IDs, role ARNs, and domains in one place. Change accounts by editing one file.
- **Manual gate for prod**: deploy job has `when: manual` on the prod branch.
- **Rollback**: trigger with `ROLLBACK_TAG=<previous-tag>` to redeploy a known-good image.

### Setup (GitLab.com)

1. Create a project on GitLab.com (free tier works) and push this repo.
2. **AWS OIDC (once per target account)** — no AWS keys are stored on the runner:
   - Create an IAM OIDC identity provider for your GitLab server URL
     (provider URL = `https://gitlab.com`, audience = `https://gitlab.com`).
   - Create an IAM role (default name `platform-deploy`) whose trust policy
     allows that provider, conditioned on
     `gitlab.com:sub` matching `project_path:<group>/<project>:ref_type:branch:ref:dev`
     (tighten per branch/environment). Grant it ECR push + EKS access, and map
     it into the cluster's access entries so `helm` can deploy.
3. Set CI/CD variables (Settings → CI/CD → Variables):
   `DEV_ACCOUNT_ID` (+ `STAGE_ACCOUNT_ID`/`PROD_ACCOUNT_ID` as needed),
   `AWS_REGION`, `ECR_REPO_NAME`, and `DEPLOY_ROLE_NAME` if not `platform-deploy`.
4. Use GitLab.com shared runners (or register your own).
5. Push to the `dev` branch → the pipeline runs automatically.

### Validate end-to-end with the shipped example

The repo includes a concrete, runnable instantiation of the pattern using the
demo services in `examples/` — so you can validate build → deploy without first
authoring a `services/` tree:

1. Apply `examples/sample-services/terraform` to create the SQS queue, S3
   bucket, and the `<env>-sample-producer` / `<env>-sample-consumer` IRSA roles.
2. Add CI/CD variables `SAMPLE_QUEUE_URL` and `SAMPLE_BUCKET` (Terraform outputs).
3. Edit a file under `examples/sample-producer/` (or `examples/sample-consumer/`)
   on the `dev` branch — the matching `trigger-sample-*` child pipeline builds the
   image, pushes to ECR, and `helm upgrade`s it onto the cluster.
4. Or force a run from the UI with pipeline variable `SERVICE=sample-producer`.

### Adding a new service

1. Create `services/<name>/` with Dockerfile and `helm-values.yaml`
2. Add trigger block to root `.gitlab-ci.yml` (copy any existing trigger)
3. Create `services/<name>/.gitlab-ci.yml` extending `.base_build` + `.base_deploy`
4. Push to `dev` branch

## Security model

| Layer | Mechanism |
|-------|-----------|
| GitHub → AWS | OIDC (no stored credentials) |
| GitLab → AWS | OIDC id_token → `assume-role-with-web-identity` (no stored keys) |
| Prod deploy gate | GitHub: environment protection. GitLab: `when: manual` |
| Secret management | GitHub: repository variables. GitLab: CI/CD variables (masked) |
| Image provenance | ECR tag = `{service}-{env}-{pipeline_id}` (traceable to exact pipeline) |

## AI merge-request review (optional, Bedrock)

An advisory, MR-triggered job (`ai-mr-review`) sends the MR diff plus this repo's
own context — ADRs (`docs/decisions/`), OPA policies (`policies/opa/`), and
`docs/ARCHITECTURE.md` — to an Amazon Bedrock Claude model and posts the review
as an MR comment. It flags IAM/IRSA over-scoping, secrets, network exposure, and
ADR/policy conflicts. It is a **soft gate** (`allow_failure: true`); set
`AI_REVIEW_BLOCK_ON_HIGH=true` to fail the job on a High-severity `BLOCK` verdict.

Auth uses the same GitLab-OIDC mechanism as deploys, but a **separate role**
scoped to **only `bedrock:InvokeModel`** — no ECR/EKS/deploy access. It is created
by `0710-cicd-oidc` (`ai_review_enabled = true`, role `platform-ai-review`), with
trust limited to this project's pipelines (any ref, so MR pipelines qualify).

Setup:
1. Apply `0710-cicd-oidc` with `ai_review_enabled = true` (default).
2. Enable Bedrock model access for your chosen model in the target account/region
   (default `eu.anthropic.claude-haiku-4-5-…` in `eu-central-1` keeps data in-EU).
3. CI/CD variables: `DEV_ACCOUNT_ID` (role account) and `AI_REVIEW_GITLAB_TOKEN`
   — a **project/group access token with `api` scope** (used to post the note;
   masked). Optional: `BEDROCK_MODEL_ID`, `AI_REVIEW_ROLE_NAME`, `AWS_REGION`.
4. Open an MR — the job runs review-only (deploy triggers are guarded off on
   `merge_request_event`).

> Note: an IAM Identity Center user cannot be used by CI (interactive SSO).
> Always federate via OIDC to a dedicated, least-privilege role as above —
> never a management-account admin.
