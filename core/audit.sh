#!/usr/bin/env bash
# =============================================================================
# core/audit.sh — Audit trail for all deploy operations
# =============================================================================

AUDIT_LOG="${AUDIT_LOG:-/app/deploy/deploy.log}"

# Initialize audit log with header if it doesn't exist
audit_init() {
  if [[ ! -f "$AUDIT_LOG" ]]; then
    mkdir -p "$(dirname "$AUDIT_LOG")"
    echo "# Deploy Audit Log — Created $(date '+%Y-%m-%d %H:%M:%S %Z')" > "$AUDIT_LOG"
    echo "# Format: TIMESTAMP | USER | ACTION | COMPONENT | VERSION | STATUS | DETAILS" >> "$AUDIT_LOG"
    echo "---" >> "$AUDIT_LOG"
  fi
}

# Record an audit entry
audit_log() {
  local action="$1" component="${2:-}" version="${3:-}" status="${4:-OK}" details="${5:-}"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  local user
  user="$(whoami)"

  audit_init
  printf '%s | %s | %s | %s | %s | %s | %s\n' \
    "$timestamp" "$user" "$action" "$component" "$version" "$status" "$details" >> "$AUDIT_LOG"
}

# Show recent audit entries
audit_recent() {
  local count="${1:-10}"
  audit_init
  echo
  echo "=== Recent Deploy Operations (last $count) ==="
  echo
  tail -n "$count" "$AUDIT_LOG" | grep -v '^#' | grep -v '^---'
  echo
}

# Show full audit log
audit_full() {
  audit_init
  echo
  echo "=== Full Deploy Audit Log ==="
  echo
  cat "$AUDIT_LOG"
  echo
}
