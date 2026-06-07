# ADR-005 — Native AWS Terraform modules over ManagedKube wrapper

**Status**: Accepted
**Date**: 2026-05

## Context

The repository scaffold was inspired by `ManagedKube/kubernetes-ops`, which uses its own Terraform module wrappers (`ManagedKube/aws/eks`, `ManagedKube/aws/vpc`, etc.) on top of AWS resources. These wrappers introduce a dependency tree: the platform code depends on ManagedKube wrappers, which depend on community modules, which depend on the AWS provider.

For a blueprint meant to be readable, copyable, and maintainable by independent engineers, this wrapping layer is overhead with limited payback.

## Decision

Replace ManagedKube wrappers with:
- Direct community modules where the community module is high quality and widely adopted: `terraform-aws-modules/vpc/aws`, `terraform-aws-modules/eks/aws`.
- Native AWS resources (`aws_*`) for everything else: Route53 zones, IRSA roles, ECR repos, RDS, Aurora, S3, EFS, SQS.

## Consequences

**Positive**:
- Fewer layers of indirection. A reader can trace from `main.tf` to the AWS API in one or two hops.
- No dependency on a third-party wrapper's release cadence or breaking changes.
- Easier to copy a single module out of the repo into another project.
- `terraform-aws-modules` (community) is mature, widely used, and well-documented. It's a reasonable dependency.

**Negative**:
- More code per module. ManagedKube wrappers compress some boilerplate.
- Engineers must understand the underlying AWS resources, not just the wrapper's interface. (This is arguably a positive for senior engineers.)

## Alternatives considered

- **Continue with ManagedKube wrappers** — fastest path but contradicts the blueprint goal of being a clear reference.
- **Pure native AWS resources, no community modules** — too verbose, especially for VPC and EKS, which the community modules handle well.
- **Crossplane/Pulumi instead of Terraform** — orthogonal. Terraform was chosen because the target audience expects it.

## Acknowledgement

ManagedKube/kubernetes-ops is acknowledged in the README as the source of inspiration for the directory layout and category-based organization, even though the implementation is independent.
