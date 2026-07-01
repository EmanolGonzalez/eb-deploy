#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/health/commands/full.sh — Full health check with dependency validation
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/health-common.sh"
source "$MODULE_DIR/../../core/health.sh"
source "$MODULE_DIR/../../core/config.sh"

echo
divider
echo "  FULL HEALTH CHECK"
divider

log "Verificando versiones instaladas..."
print_status 2>/dev/null || true

echo
load_config || true
check_db_connection

echo
check_external_services

echo
if [[ -L "/app/backend/current" ]]; then
  log "Healthcheck backend..."
  run_healthcheck backend --soft || true
fi

if [[ -L "/app/frontend/current" ]]; then
  log "Healthcheck frontend..."
  run_healthcheck frontend --soft || true
fi

echo
divider
ok "Health check completo finalizado."
