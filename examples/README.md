# Sample services — producer + consumer demo

End-to-end demonstration of the platform's primitives:
**HTTP → SQS → S3** with two services using **scoped IRSA roles**.

```
┌──────────┐   POST /messages    ┌──────────────┐
│  Client  │ ──────────────────▶ │  Producer    │
└──────────┘                     │              │
                                 │ SQS:Send     │
                                 ▼              │
                          ┌─────────────┐       │
                          │   SQS queue │       │
                          └──────┬──────┘       │
                                 │              │
                                 │ Long-poll    │
                                 ▼              │
                          ┌──────────────┐      │
                          │   Consumer   │      │
                          │              │      │
                          │ SQS:Receive  │      │
                          │ S3:PutObject │      │
                          ▼              │      │
                          ┌─────────────┐       │
                          │  S3 bucket  │       │
                          │ processed/  │       │
                          │ <id>.json   │       │
                          └─────────────┘       │
                                                │
                          GET /metrics ◀────────┘
```

## What this demonstrates

- **Two services with separate IRSA roles** — producer can only `SendMessage`, consumer can only `Receive/Delete` + `PutObject`. Compromise of producer pod cannot read messages or write to S3.
- **Async pattern** — producer returns 202 immediately, work happens in consumer.
- **Long-polling SQS** — efficient receive (no busy loop).
- **Prometheus metrics** — both services expose counters; observability is platform-native.
- **Gateway API routing** — producer is exposed externally; consumer is internal-only.

## Layout

```
examples/
├── sample-producer/      # Go HTTP service: POST /messages → SQS
├── sample-consumer/      # Go service: SQS → S3
└── sample-services/
    └── terraform/        # SQS queue + S3 bucket + scoped IRSA roles
```

## Deploy

### 1. Apply the demo Terraform

Creates the S3 bucket and two IRSA roles (producer + consumer) referencing
the SQS queue created by `0410-messaging`.

Prerequisite: `0410-messaging` must already register a queue named `sample-events`.
Add this to your `0410-messaging/terraform.tfvars`:

```hcl
queues = {
  sample-events = {
    visibility_timeout_seconds = 60
  }
}
```

Then:

```bash
cd examples/sample-services/terraform
cp terraform.tfvars.example terraform.tfvars
# edit state_bucket
terraform init -backend-config="bucket=<your-state-bucket>" \
               -backend-config="key=dev/examples/sample-services/terraform.tfstate" \
               -backend-config="region=eu-central-1" \
               -backend-config="dynamodb_table=<your-lock-table>" \
               -backend-config="encrypt=true"
terraform apply

# Capture the deploy commands
terraform output -raw deploy_command_producer
terraform output -raw deploy_command_consumer
```

### 2. Build images

```bash
cd examples/sample-producer
docker build -t <ecr-registry>/sample-producer:dev-1 .
docker push <ecr-registry>/sample-producer:dev-1

cd ../sample-consumer
docker build -t <ecr-registry>/sample-consumer:dev-1 .
docker push <ecr-registry>/sample-consumer:dev-1
```

### 3. Deploy with Helm

Use the `deploy_command_*` outputs from step 1, then add:
```
--set image.registry=<ecr-registry>
--set image.tag=dev-1
```

### 4. Test the flow

```bash
# Find the producer URL from the Istio gateway
PRODUCER_URL=$(kubectl get svc -n istio-ingress istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Send a message
curl -X POST http://$PRODUCER_URL/producer/messages \
  -H 'Content-Type: application/json' \
  -d '{"text": "hello platform", "metadata": {"source": "smoke-test"}}'

# Expected: 202 Accepted with messageId

# Verify it landed in S3
aws s3 ls s3://<bucket-name>/processed/

# Check consumer metrics
kubectl port-forward -n sample-consumer svc/sample-consumer 8080:8080 &
curl localhost:8080/metrics | grep sample_consumer_messages_processed_total
```

## What you should see

- Producer returns 202 with the SQS messageId
- Consumer logs show `processed message` within ~20 seconds (long-poll wait)
- S3 has `processed/<messageId>.json`
- Prometheus metrics: `sample_producer_messages_enqueued_total` and
  `sample_consumer_messages_processed_total` both increment
- Grafana (if Loki is deployed) shows logs from both services correlated by
  messageId

## Failure scenarios to try

- **Kill the consumer** — messages accumulate in the queue. Restart consumer; it catches up.
- **Send a malformed message that the consumer can't process** — after `maxReceiveCount` (default 5) failed receives, message moves to DLQ. CloudWatch alarm fires (if `alert_email` is set in 0410-messaging).
- **Revoke the producer's IRSA role** in IAM — producer fails to send; observability shows the failure metric increment.

These exercises validate that the platform's primitives are wired correctly and
the IRSA scoping is enforced.
