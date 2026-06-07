# 0010-state-backend

Bootstraps the shared Terraform state infrastructure: an S3 bucket (versioned, encrypted, public-access-blocked) and a DynamoDB table for state locking.

## Apply once, before anything else

```bash
cd terraform/backend/0010-state-backend
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project name and region

terraform init
terraform plan
terraform apply
```

After this, all other modules reference the bucket and table in their `backend "s3" {}` blocks.

## Why local state?

This module creates the S3 backend — it can't use the backend it creates. It uses `backend "local" {}`. The resulting `terraform.tfstate` file is small and changes rarely. Options for protecting it:

1. Commit it to a **private** repository (not this public one)
2. Store it in a secure location (e.g., 1Password, AWS Secrets Manager)
3. Accept the risk: the module is idempotent — if state is lost, `terraform apply` re-detects existing resources

## Resources created

| Resource | Name pattern | Purpose |
|----------|-------------|---------|
| `aws_s3_bucket` | `{project_name}-terraform-state` | State file storage |
| `aws_dynamodb_table` | `{project_name}-terraform-locks` | State locking (partition key: `LockID`) |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | `"platform"` | Prefix for bucket and table names |
| `aws_region` | `"eu-central-1"` | Region for state infrastructure |
| `tags` | `{}` | Additional tags merged with defaults |
