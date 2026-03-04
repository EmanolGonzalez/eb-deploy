#!/usr/bin/env bash
set -e

# =============================================================================
# healthcheck.sh — Application health validation
# Validates that the application is running and healthy after install/update.
# =============================================================================

COMPONENT="backend"
SOFT_MODE=false

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      backend|frontend)
        COMPONENT="$1"
        shift
        ;;
      --soft)
        SOFT_MODE=true
        shift
        ;;
      --strict)
        SOFT_MODE=false
        shift
        ;;
      *)
        echo "Error: unknown argument '$1'" >&2
        echo "Usage: bash healthcheck.sh [backend|frontend] [--soft|--strict]" >&2
        exit 2
        ;;
    esac
  done
}

fail_or_warn() {
  local message="$1"
  if [[ "$SOFT_MODE" == true ]]; then
    echo "Warn: $message"
    return 0
  fi

  echo "Error: $message" >&2
  exit 1
}

parse_args "$@"

if [[ "$COMPONENT" == "frontend" ]]; then
  FRONTEND_CURRENT_LINK="/app/frontend/current"
  FRONTEND_INDEX_FILE="${FRONTEND_CURRENT_LINK}/index.html"

  echo "==> Checking frontend current symlink $FRONTEND_CURRENT_LINK"
  if [[ ! -L "$FRONTEND_CURRENT_LINK" ]]; then
    fail_or_warn "frontend current symlink not found."
    [[ "$SOFT_MODE" == true ]] && exit 0
  fi

  echo "==> Checking frontend artifact $FRONTEND_INDEX_FILE"
  if [[ ! -f "$FRONTEND_INDEX_FILE" ]]; then
    fail_or_warn "frontend index file not found in current release."
    [[ "$SOFT_MODE" == true ]] && exit 0
  fi

  echo "Healthcheck passed successfully"
  exit 0
fi

APP_NAME="backend"
BACKEND_RELEASE_DIR="/app/backend/current"
MAX_RETRIES="${HEALTHCHECK_RETRIES:-20}"
SLEEP_SECONDS="${HEALTHCHECK_SLEEP_SECONDS:-3}"

collect_candidate_ports() {
  local ports=()

  if [[ -n "${APP_PORT:-}" ]]; then
    ports+=("$APP_PORT")
  fi

  if [[ -n "${BACKEND_PORTS:-}" ]]; then
    for p in ${BACKEND_PORTS//,/ }; do
      ports+=("$p")
    done
  fi

  if [[ -d "$BACKEND_RELEASE_DIR" ]]; then
    while IFS= read -r p; do
      ports+=("$p")
    done < <(grep -h -oE 'http://localhost:[0-9]+' "$BACKEND_RELEASE_DIR"/appsettings*.json 2>/dev/null | sed -E 's#.*:([0-9]+)$#\1#')
  fi

  ports+=("5000")

  printf '%s\n' "${ports[@]}" | awk '/^[0-9]+$/{print}' | awk '!seen[$0]++'
}

mapfile -t PORT_CANDIDATES < <(collect_candidate_ports)
if [[ ${#PORT_CANDIDATES[@]} -eq 0 ]]; then
  PORT_CANDIDATES=("5000")
fi

echo "==> Candidate backend ports: ${PORT_CANDIDATES[*]}"

# ----------------------------------------------------------------------------
# Check if the systemd service is active
# ----------------------------------------------------------------------------
echo "==> Checking if service $APP_NAME is active"
if ! systemctl is-active --quiet "$APP_NAME"; then
  fail_or_warn "service $APP_NAME is not active."
  [[ "$SOFT_MODE" == true ]] && exit 0
fi

# ----------------------------------------------------------------------------
# Wait for backend to listen and return healthy response
# ----------------------------------------------------------------------------
health_paths=("/api/health" "/health" "/healthz")
healthy=false

for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
  if ! systemctl is-active --quiet "$APP_NAME"; then
    echo "==> Attempt $attempt/$MAX_RETRIES: service not active yet"
    sleep "$SLEEP_SECONDS"
    continue
  fi

  for port in "${PORT_CANDIDATES[@]}"; do
    if ss -tulnp | grep -q ":${port}\\b"; then
      echo "==> Attempt $attempt/$MAX_RETRIES: port $port is listening"
      for path in "${health_paths[@]}"; do
        endpoint="http://localhost:${port}${path}"
        if curl -fs --max-time 3 "$endpoint" > /dev/null; then
          echo "==> Health endpoint OK: $endpoint"
          healthy=true
          break 3
        fi
      done
    fi
  done

  sleep "$SLEEP_SECONDS"
done

if [[ "$healthy" != true ]]; then
  fail_or_warn "backend did not become healthy after $MAX_RETRIES attempts."
  echo "Tip: check logs with: journalctl -u backend -n 60 --no-pager" >&2
  [[ "$SOFT_MODE" == true ]] && exit 0
fi

# ----------------------------------------------------------------------------
# Success
# ----------------------------------------------------------------------------
echo "Healthcheck passed successfully"
exit 0
