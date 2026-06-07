# Network Topology

## Single-account view (evaluation mode)

```
                                    Internet
                                       │
                         ┌─────────────▼──────────────┐
                         │    AWS NLB (public)        │
                         │   (created by Istio GW)    │
                         └─────────────┬──────────────┘
                                       │
┌──────────────────────────────────────▼─────────────────────────────────┐
│  VPC 10.0.0.0/16                                                       │
│                                                                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │ Public  10.0.0  │  │ Public  10.0.1  │  │ Public  10.0.2  │ AZs     │
│  │ /20 (a)         │  │ /20 (b)         │  │ /20 (c)         │         │
│  └─────────┬───────┘  └─────────┬───────┘  └─────────┬───────┘         │
│            │ NAT GW              │                    │                │
│  ┌─────────▼───────┐  ┌─────────▼───────┐  ┌─────────▼───────┐         │
│  │ Private 10.0.16 │  │ Private 10.0.32 │  │ Private 10.0.48 │ AZs     │
│  │ /20 (a)         │  │ /20 (b)         │  │ /20 (c)         │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│                                                                        │
│  Secondary CIDR: 100.64.0.0/16 (RFC 6598) — used for pod IPs           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │ Pods 100.64.0   │  │ Pods 100.64.16  │  │ Pods 100.64.32  │         │
│  │ /20 (a)         │  │ /20 (b)         │  │ /20 (c)         │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────┐        │
│  │ EKS cluster — control plane in private subnets             │        │
│  │ Nodes in private subnets, pods on secondary CIDR           │        │
│  └────────────────────────────────────────────────────────────┘        │
└────────────────────────────────────────────────────────────────────────┘
```

### Why a secondary CIDR for pods

EKS with the AWS VPC CNI assigns one IP per pod from the VPC. With ~30 pods per
node × 6 nodes, you exhaust a `/24` quickly. The standard fix is to attach a
secondary CIDR (RFC 6598 `100.64.0.0/10` is reserved for carrier-grade NAT and
unlikely to collide with anything) and configure the CNI to allocate from it.

See `terraform/environments/dev/0110-vpc/main.tf` for the implementation.

## Multi-account production view

```
              ┌─────────────────────────────────────┐
              │  Management account                 │
              │  - ECR (shared)                     │
              │  - Route53 hosted zone (delegate)   │
              │  - Transit Gateway (hub)            │
              └────────────┬────────────────────────┘
                           │ TGW peering
       ┌───────────────────┼───────────────────┐
       │                   │                   │
┌──────▼─────┐      ┌──────▼─────┐      ┌──────▼─────┐
│ Dev acct   │      │ Stage acct │      │ Prod acct  │
│ VPC 10.0   │      │ VPC 10.1   │      │ VPC 10.2   │
│ EKS dev    │      │ EKS stage  │      │ EKS prod   │
└────────────┘      └────────────┘      └────────────┘
```

Cross-VPC traffic flows through the TGW. ECR images are pulled cross-account via
ECR repository policies granting workload accounts pull access.

See [ADR-001](decisions/ADR-001-multi-account-topology.md).

> **TGW creation is not in this repo.** The `0120-tgw-attachment` module is the
> workload-side attachment to a TGW that's expected to exist in the management
> account (typically created via a separate `accounts/management/0140-transit-gateway`
> module and shared via AWS RAM). Not needed for single-account evaluation —
> see [ADR-009](decisions/ADR-009-single-account-evaluation-mode.md).

## Internal vs external gateways

Production has two Istio Gateways:

- **External (`0650-istio-gateway`)** — public NLB, exposes user-facing services
- **Internal (`0660-istio-gateway-internal`)** — internal NLB, exposes
  service-to-service routing within the VPC and across TGW peering

Dev evaluation mode runs only the external gateway over HTTP.

## Security boundaries

| Layer | Boundary | Mechanism |
|-------|----------|-----------|
| Account | IAM Organization | Cross-account roles |
| VPC | Subnet isolation | Public/private subnets, NACLs |
| Pod | Network policy (optional) | Cilium or Istio AuthorizationPolicy |
| Workload | IAM | IRSA per ServiceAccount |
| Data | Encryption | KMS for EBS, RDS, Aurora, S3 |

Public ingress is restricted to ports 80/443 by [policies/opa/network-rules.rego](../policies/opa/network-rules.rego).
