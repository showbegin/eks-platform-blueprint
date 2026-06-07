# CI/CD

This blueprint uses two CI systems for two different concerns:

- **GitHub Actions** for infrastructure (Terraform). OIDC to AWS, plan-on-PR, gated apply.
- **GitLab CI** for applications (Docker + Helm). Monorepo SERVICE-variable dispatch, fast iteration.

For full setup instructions, security model, and adding new services:

→ **[`ci/README.md`](../ci/README.md)**

For the rationale behind dual CI:

→ **[ADR-004](decisions/ADR-004-dual-ci.md)**
