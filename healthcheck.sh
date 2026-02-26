#!/usr/bin/env bash
set -e

# =============================================================================
# healthcheck.sh — Application health validation
# Validates that the application is running and healthy after install/update.
# =============================================================================

APP_NAME="backend"
PORT="${APP_PORT:-5000}"
HEALTH_ENDPOINT="http://localhost:${PORT}/api/health"

# ----------------------------------------------------------------------------
# Check if the systemd service is active
# ----------------------------------------------------------------------------
echo "==> Checking if service $APP_NAME is active"
if ! systemctl is-active --quiet "$APP_NAME"; then
  echo "Error: service $APP_NAME is not active." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Check if the port is listening
# ----------------------------------------------------------------------------
echo "==> Checking if port $PORT is listening"
if ! ss -tulnp | grep ":$PORT" > /dev/null; then
  echo "Error: port $PORT is not listening." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Check if the health endpoint responds with 200
# ----------------------------------------------------------------------------
echo "==> Checking health endpoint $HEALTH_ENDPOINT"
if ! curl -fs "$HEALTH_ENDPOINT" > /dev/null; then
  echo "Error: health endpoint $HEALTH_ENDPOINT did not return 200." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Success
# ----------------------------------------------------------------------------
echo "Healthcheck passed successfully"
exit 0
