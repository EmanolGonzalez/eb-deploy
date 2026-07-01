#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/health/commands/set-endpoint.sh — Configure health endpoint
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/health-common.sh"

CONFIG_FILE="/app/config/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "Archivo de configuracion no encontrado: $CONFIG_FILE"
  exit 1
fi

CURRENT="$(read_config_value "BACKEND_HEALTH_ENDPOINT")"
if [[ -n "$CURRENT" ]]; then
  log "Endpoint actual: $CURRENT"
fi

read -rp "Nuevo endpoint (ej: http://localhost:5000/api/health): " NEW_ENDPOINT
if [[ -z "$NEW_ENDPOINT" ]]; then
  err "El endpoint es obligatorio."
  exit 1
fi

update_config_value "BACKEND_HEALTH_ENDPOINT" "$NEW_ENDPOINT"
ok "BACKEND_HEALTH_ENDPOINT guardado en $CONFIG_FILE"

# Validate immediately.
# -k: si el endpoint es HTTPS interno con cert propio/self-signed, no validar el
# cert (servers internos sin CA valida). El healthcheck solo confirma que responde.
log "Validando endpoint..."
if curl -fsSk "$NEW_ENDPOINT" >/dev/null 2>&1; then
  ok "Endpoint respondiendo correctamente (HTTP 200)."
else
  warn "El endpoint no respondio con HTTP 200. Verifica la configuracion."
fi
