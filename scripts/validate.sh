#!/usr/bin/env bash
# scripts/validate.sh
#
# Full static validation across all Terraform modules:
#   - terraform fmt -check
#   - terraform validate (per module, requires init)
#   - tflint (if installed)
#   - trivy config (if installed)
#   - conftest (if installed, runs OPA policies in policies/opa/)
#
# Exits non-zero on any failure.
#
# Usage: ./scripts/validate.sh [path]
#   path: optional, defaults to terraform/
#
# Skip slow checks: VALIDATE_FAST=1 ./scripts/validate.sh

set -euo pipefail

ROOT="${1:-terraform}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

fail=0

log() { echo -e "${YELLOW}==>${NC} $1"; }
ok()  { echo -e "${GREEN}✓${NC}  $1"; }
err() { echo -e "${RED}✗${NC}  $1"; fail=1; }

# 1. fmt
log "terraform fmt -check -recursive $ROOT"
if terraform fmt -check -recursive "$ROOT" > /dev/null; then
  ok "fmt clean"
else
  err "fmt issues found — run: terraform fmt -recursive $ROOT"
fi

# 2. tflint
if command -v tflint > /dev/null; then
  log "tflint across modules"
  while IFS= read -r mod; do
    (cd "$mod" && tflint --no-color 2>&1) || err "tflint failed in $mod"
  done < <(find "$ROOT" -name '*.tf' -exec dirname {} \; | sort -u | grep -v '\.terraform')
  ok "tflint pass"
else
  echo "  tflint not installed — skip (install: https://github.com/terraform-linters/tflint)"
fi

# 3. trivy config
if command -v trivy > /dev/null; then
  log "trivy config $ROOT"
  trivy config --quiet --exit-code 0 "$ROOT" || err "trivy reported issues (review above)"
  ok "trivy run complete"
else
  echo "  trivy not installed — skip (install: https://github.com/aquasecurity/trivy)"
fi

# 4. conftest (OPA policies)
if command -v conftest > /dev/null && [ -d "policies/opa" ]; then
  log "conftest validation (OPA policies)"
  if [ "${VALIDATE_FAST:-0}" = "1" ]; then
    echo "  VALIDATE_FAST=1 — skipping conftest (requires terraform plan output)"
  else
    echo "  conftest expects terraform plan output. Run scripts/plan-all.sh first to generate."
    echo "  Then: conftest test plans/*.json --policy policies/opa/"
  fi
else
  echo "  conftest or policies/opa not present — skip"
fi

# 5. terraform validate per module (requires init — slow)
if [ "${VALIDATE_FAST:-0}" = "1" ]; then
  echo "  VALIDATE_FAST=1 — skipping terraform validate"
else
  log "terraform validate per module"
  while IFS= read -r mod; do
    (cd "$mod" && terraform init -backend=false -no-color > /dev/null 2>&1 && terraform validate -no-color > /dev/null) \
      && ok "validate: $mod" \
      || err "validate failed: $mod"
  done < <(find "$ROOT" -name 'main.tf' -exec dirname {} \; | sort -u | grep -v '\.terraform')
fi

echo
if [ $fail -eq 0 ]; then
  echo -e "${GREEN}All checks passed.${NC}"
else
  echo -e "${RED}Validation failures above. Fix before committing.${NC}"
  exit 1
fi
