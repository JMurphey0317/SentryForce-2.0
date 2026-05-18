#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

check() {
  local pattern="$1"
  local path="$2"
  if grep -R --line-number --fixed-strings "$pattern" "$ROOT/$path" >/dev/null 2>&1; then
    echo "[ERROR] Found placeholder '$pattern' in $path"
    grep -R --line-number --fixed-strings "$pattern" "$ROOT/$path" || true
    EXIT=1
  fi
}

check "REPLACE_WITH_ADMIN_EMAIL" "force-app/main/default/transactionSecurityPolicies"
check "REPLACE_WITH_CICD_USERNAME" "force-app/main/default/flows"
check "REPLACE_WITH_SLACK_WEBHOOK" "force-app/main/default/customMetadata"

if [[ "$EXIT" -eq 0 ]]; then
  echo "No placeholder values found."
fi

exit "$EXIT"
