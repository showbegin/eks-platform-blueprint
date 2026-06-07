#!/usr/bin/env bash
# scripts/destroy-all.sh
#
# Destroys every module in an environment in REVERSE XXYZ order.
# Critical: dependents (Helm operators, 06xx) must be destroyed before
# the cluster (0210) and VPC (0110).
#
# Usage:
#   ./scripts/destroy-all.sh dev          # destroys dev with confirmation
#   FORCE=1 ./scripts/destroy-all.sh dev  # no confirmation (CI/scripted use)

set -euo pipefail

ENV="${1:-}"
if [ -z "$ENV" ]; then
  echo "Usage: $0 <env>" >&2
  exit 1
fi

ROOT="terraform/environments/${ENV}"
if [ ! -d "$ROOT" ]; then
  echo "Environment not found: $ROOT" >&2
  exit 1
fi

if [ "${FORCE:-0}" != "1" ]; then
  echo "About to DESTROY all resources in environment: $ENV"
  echo "This is irreversible. Type the environment name to confirm:"
  read -r confirmation
  if [ "$confirmation" != "$ENV" ]; then
    echo "Confirmation mismatch. Aborting."
    exit 1
  fi
fi

# Modules in REVERSE XXYZ order (highest first)
modules=$(find "$ROOT" -maxdepth 1 -mindepth 1 -type d | sort -r)

for mod in $modules; do
  name=$(basename "$mod")
  echo
  echo "=========================================="
  echo "  Destroy: $name"
  echo "=========================================="
  (
    cd "$mod"
    terraform init -no-color > /dev/null
    terraform destroy -auto-approve -no-color
  ) || { echo "Destroy failed for $name — manual intervention required"; exit 1; }
done

echo
echo "Environment $ENV fully destroyed."
echo "Verify in AWS console: no orphan ENIs, EBS volumes, or load balancers."
