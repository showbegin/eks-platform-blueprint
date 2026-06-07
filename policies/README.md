# Policy as Code

Policies in this directory enforce platform invariants — the things that should
**never** be true regardless of who's writing the Terraform. They run in CI on
every plan and fail builds that violate them.

## Why a policy layer

Most infra problems start as a small omission (no encryption flag, missing tag,
0.0.0.0/0 left open in a hurry). They compound into incidents and audit
findings. A policy layer catches them at PR time, not in production.

This directory contains [Open Policy Agent (OPA)](https://www.openpolicyagent.org/)
policies in [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/),
evaluated by [conftest](https://www.conftest.dev/).

## Policies

| File | Enforces |
|------|----------|
| `opa/resource-tagging.rego` | Required tags (Project, Environment, ManagedBy) on all taggable resources |
| `opa/encryption-required.rego` | Encryption at rest for S3, RDS, Aurora, EBS, EFS |
| `opa/network-rules.rego` | No public 0.0.0.0/0 except 80/443; RDS not publicly accessible; EKS endpoint restricted |

## Running locally

```bash
# 1. Install conftest
brew install conftest                    # macOS
# or: https://www.conftest.dev/install/

# 2. Generate plan output across modules
./scripts/plan-all.sh dev

# 3. Test against policies
conftest test plans/*.json --policy policies/opa/
```

## Adding a new policy

1. Create `opa/<rule-name>.rego` with `package terraform.<topic>`.
2. Test locally against existing plans.
3. Document in this README.
4. Add to CI by no-op (CI runs all `.rego` in `policies/opa/`).

## Sentinel as alternative

This repo uses OPA because it's open-source and tool-agnostic. Teams running
HashiCorp Cloud Platform may prefer Sentinel — same intent, different syntax.
The Rego policies here can be ported to Sentinel mechanically.
