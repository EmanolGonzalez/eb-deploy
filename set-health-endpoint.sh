#!/usr/bin/env bash
set -e

HEALTH_ENDPOINT_FILE="/app/config/backend-health-endpoint.txt"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

require_root

if [[ -n "${1:-}" ]]; then
  HEALTH_ENDPOINT="$1"
else
  read -rp "Enter backend health endpoint URL (e.g. http://localhost:5000/api/health): " HEALTH_ENDPOINT
fi

if [[ -z "$HEALTH_ENDPOINT" ]]; then
  err "Health endpoint is required."
  exit 1
fi

mkdir -p /app/config
printf '%s' "$HEALTH_ENDPOINT" > "$HEALTH_ENDPOINT_FILE"
chmod 600 "$HEALTH_ENDPOINT_FILE"
log "Backend health endpoint saved in $HEALTH_ENDPOINT_FILE"

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_ENDPOINT" || true)"
if [[ "$HTTP_CODE" == "200" ]]; then
  log "Validation OK (HTTP 200): $HEALTH_ENDPOINT"
else
  log "Validation warning (HTTP $HTTP_CODE): $HEALTH_ENDPOINT"
fi

log "Done."
