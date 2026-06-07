#!/usr/bin/env bash
# scripts/plan-all.sh
#
# Runs `terraform plan` for every module in an environment, in XXYZ order.
# Useful for end-to-end review of pending changes.
#
# Usage:
#   ./scripts/plan-all.sh dev
#   ./scripts/plan-all.sh prod

set -euo pipefail

ENV="${1:-dev}"
ROOT="terraform/environments/${ENV}"

if [ ! -d "$ROOT" ]; then
  echo "Environment not found: $ROOT" >&2
  exit 1
fi

mkdir -p plans

# Modules sorted by XXYZ prefix (numeric)
modules=$(find "$ROOT" -maxdepth 1 -mindepth 1 -type d | sort)

for mod in $modules; do
  name=$(basename "$mod")
  echo
  echo "=========================================="
  echo "  Plan: $name"
  echo "=========================================="
  (
    cd "$mod"
    terraform init -no-color > /dev/null
    terraform plan -no-color -out="../../../../plans/${ENV}-${name}.binary"
    terraform show -json "../../../../plans/${ENV}-${name}.binary" > "../../../../plans/${ENV}-${name}.json"
  ) || { echo "Plan failed for $name"; exit 1; }
done

echo
echo "Plans saved to plans/. Validate with OPA:"
echo "  conftest test plans/*.json --policy policies/opa/"
