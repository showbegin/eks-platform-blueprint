# Quickstart — Single AWS Account

Deploy the full platform in a single AWS account without cross-account roles,
custom domains, or ACM certificates. Ideal for evaluation and learning.

## Prerequisites

- AWS account with admin access
- AWS CLI configured (`aws sts get-caller-identity` works)
- Terraform >= 1.5
- Helm >= 3.14
- kubectl

## What you'll deploy

```
0010-state-backend  → S3 + DynamoDB for Terraform state
0110-vpc            → VPC with public/private/EKS subnets
0210-eks            → EKS cluster (1.34, Bottlerocket nodes)
0630-istio-base     → Istio CRDs
0640-istiod         → Istio control plane (Gateway API enabled)
0650-istio-gateway  → Edge gateway (HTTP-only, no cert needed)
0610-cert-manager   → cert-manager + self-signed ClusterIssuer
0670-kube-prometheus-stack → Prometheus + Grafana
```

## Estimated cost

| Resource | Hourly | Daily | Monthly |
|----------|--------|-------|---------|
| EKS control plane | $0.10 | $2.40 | $73 |
| 2x m6g.xlarge nodes | $0.31 | $7.44 | $226 |
| NAT Gateway (1 AZ) | $0.045 | $1.08 | $33 |
| EBS (200GB gp3 × 2) | — | — | $32 |
| S3 + DynamoDB | — | — | ~$1 |
| **Total** | **~$0.46** | **~$11** | **~$365** |

**Evaluation tip**: Deploy Friday evening, evaluate over the weekend, destroy Sunday night → ~$22 total.

## One-time setup — Terraform plugin cache

Each module pulls its own provider binaries by default (~600MB per module).
With 20+ modules, this means ~12GB of duplicate downloads. Configure a shared
cache once:

```bash
./scripts/setup-terraform-cache.sh
```

This adds `plugin_cache_dir` to `~/.terraformrc`. Every subsequent `terraform
init` hard-links to the shared cache. First module: full download. All others:
seconds.

## Step-by-step

### 1. Bootstrap state backend

```bash
cd terraform/backend/0010-state-backend
cp terraform.tfvars.example terraform.tfvars
# Edit: set project_name and aws_region

terraform init
terraform apply
```

Note the outputs — you'll use `state_bucket_name` in subsequent modules.

### 2. Deploy VPC

```bash
cd ../../environments/dev/0110-vpc
cat > backend.hcl <<EOF
bucket = "<state_bucket_name from step 1>"
key    = "dev/0110-vpc/terraform.tfstate"
region = "eu-central-1"
EOF

cat > terraform.tfvars <<EOF
aws_region  = "eu-central-1"
environment = "dev"
state_bucket = "<state_bucket_name>"
# assume_role_arn is null by default — single-account mode
EOF

terraform init -backend-config=backend.hcl
terraform apply
```

### 3. Deploy EKS

```bash
cd ../0210-eks
cat > backend.hcl <<EOF
bucket = "<state_bucket_name>"
key    = "dev/0210-eks/terraform.tfstate"
region = "eu-central-1"
EOF

cat > terraform.tfvars <<EOF
aws_region   = "eu-central-1"
environment  = "dev"
state_bucket = "<state_bucket_name>"
EOF

terraform init -backend-config=backend.hcl
terraform apply  # ~15 minutes
```

After apply:
```bash
aws eks update-kubeconfig --name dev --region eu-central-1
kubectl get nodes  # Should show 2 Bottlerocket nodes
```

### 4. Deploy Istio + Gateway

```bash
# Apply in order: istio-base → istiod → istio-gateway
for mod in 0630-istio-base 0640-istiod 0650-istio-gateway; do
  cd ~/path-to-repo/terraform/environments/dev/$mod
  cat > backend.hcl <<EOF
bucket = "<state_bucket_name>"
key    = "dev/$mod/terraform.tfstate"
region = "eu-central-1"
EOF
  cat > terraform.tfvars <<EOF
aws_region   = "eu-central-1"
environment  = "dev"
state_bucket = "<state_bucket_name>"
EOF
  terraform init -backend-config=backend.hcl
  terraform apply -auto-approve
done
```

### 5. Deploy observability

```bash
cd ../0670-kube-prometheus-stack
# Same backend.hcl pattern...
cat > terraform.tfvars <<EOF
aws_region             = "eu-central-1"
environment            = "dev"
state_bucket           = "<state_bucket_name>"
grafana_admin_password = "changeme123"
EOF

terraform init -backend-config=backend.hcl
terraform apply
```

Access Grafana:
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# Open http://localhost:3000 — admin / changeme123
```

### 6. Deploy sample service (after Phase 4)

```bash
helm upgrade --install sample-service ../../helm/microservice-chart \
  --set environment=dev \
  --set hostname=sample \
  --set domain=example.internal \
  --set image.registry=nginx \
  --set image.tag=latest \
  --set app.port=80 \
  --set routing.httpRoute.enabled=false
```

## Destroy (reverse order)

```bash
# Destroy in reverse dependency order
for mod in 0670-kube-prometheus-stack 0650-istio-gateway 0640-istiod 0630-istio-base 0210-eks 0110-vpc; do
  cd ~/path-to-repo/terraform/environments/dev/$mod
  terraform destroy -auto-approve
done

# Finally, destroy state backend (requires removing S3 bucket contents first)
cd ~/path-to-repo/terraform/backend/0010-state-backend
terraform destroy
```

## Modules skipped in quickstart

These modules require additional setup and are optional for evaluation:

| Module | Why skipped | What you'd need |
|--------|-------------|-----------------|
| 0120-tgw-attachment | Multi-account only | Second AWS account + TGW |
| 0130-route53-hostedzone | Needs a domain | Registered domain in Route53 |
| 0220-eks-cluster-autoscaler | Nice-to-have | Just apply after EKS |
| 0230-bastion | SSH access | SSH key pair |
| 0310-s3, 0320-rds | Data layer | Just apply after VPC |
| 0410-messaging | App-specific | Just apply after EKS |
| 0620-external-dns | Needs Route53 zone | Domain + hosted zone |
| 0660-istio-gateway-internal | Multi-VPC traffic | TGW + peer VPC |
| 0680-grafana-loki | Log aggregation | Just apply after EKS |
