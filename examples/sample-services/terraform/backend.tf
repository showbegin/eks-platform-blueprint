# Initialize with:
#   terraform init \
#     -backend-config="bucket=<your-state-bucket>" \
#     -backend-config="key=dev/examples/sample-services/terraform.tfstate" \
#     -backend-config="region=eu-central-1" \
#     -backend-config="dynamodb_table=<your-lock-table>" \
#     -backend-config="encrypt=true"
