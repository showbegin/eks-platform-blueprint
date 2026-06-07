#!/usr/bin/env bash
# scripts/setup-terraform-cache.sh
#
# One-time setup: configures a shared Terraform plugin cache so all modules
# share provider binaries instead of each downloading its own copy.
#
# Saves ~600MB per module × ~20 modules = ~12GB of disk vs. cold init.
#
# Idempotent — safe to run multiple times.

set -euo pipefail

CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
RC_FILE="$HOME/.terraformrc"

mkdir -p "$CACHE_DIR"

if [ -f "$RC_FILE" ] && grep -q "plugin_cache_dir" "$RC_FILE"; then
  echo "✓ plugin_cache_dir already configured in $RC_FILE"
else
  cat >> "$RC_FILE" <<EOF

# Shared provider cache — hard-links instead of redownloading per-module init.
plugin_cache_dir = "$CACHE_DIR"
plugin_cache_may_break_dependency_lockfile = true
EOF
  echo "✓ Added plugin_cache_dir to $RC_FILE"
fi

echo
echo "Cache directory: $CACHE_DIR"
echo "Current size:    $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)"
echo
echo "To clean stale entries: rm -rf $CACHE_DIR && terraform init (in any module)"
