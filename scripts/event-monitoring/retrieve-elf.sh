#!/usr/bin/env bash
set -euo pipefail
ALIAS="${1:-}"
DAYS_BACK="${2:-1}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: $0 <target-org-alias> [days-back]"
  exit 1
fi
sf data query \
  --target-org "$ALIAS" \
  --query "SELECT Id, EventType, LogDate, Sequence, LogFileLength FROM EventLogFile WHERE LogDate = LAST_N_DAYS:${DAYS_BACK} ORDER BY LogDate DESC" \
  --result-format table
