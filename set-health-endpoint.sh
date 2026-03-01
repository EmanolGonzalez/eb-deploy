#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# set-health-endpoint.sh — Configura o cambia el endpoint de healthcheck del backend
# Guarda BACKEND_HEALTH_ENDPOINT en /app/config/config.env.
# status.sh usa esta URL como endpoint preferido para validar el backend.
#
# Uso:
#   bash set-health-endpoint.sh
#   bash set-health-endpoint.sh "http://localhost:5000/api/health"
# =============================================================================

CONFIG_FILE="/app/config/config.env"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }
ok()  { echo -e "\033[1;32m OK  $*\033[0m"; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

update_config_value() {
  local key="$1" value="$2"
  local safe="${value//\\/\\\\}"; safe="${safe//\"/\\\"}"
  local tmp found=false
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^"${key}=" ]]; then
      printf '%s="%s"\n' "$key" "$safe" >> "$tmp"
      found=true
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$CONFIG_FILE"
  [[ "$found" == false ]] && printf '\n%s="%s"\n' "$key" "$safe" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

require_root

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "Archivo de configuración no encontrado: $CONFIG_FILE"
  err "Ejecuta setup-server.sh primero."
  exit 1
fi

# Leer valor actual desde config.env
# shellcheck source=/dev/null
source "$CONFIG_FILE"
CURRENT_ENDPOINT="${BACKEND_HEALTH_ENDPOINT:-}"

if [[ -n "$CURRENT_ENDPOINT" ]]; then
  log "Endpoint configurado actualmente: $CURRENT_ENDPOINT"
fi

# Aceptar como argumento o pedir interactivamente
if [[ -n "${1:-}" ]]; then
  HEALTH_ENDPOINT="$1"
else
  read -rp "URL del endpoint de salud (ej: http://localhost:5000/api/health): " HEALTH_ENDPOINT
fi

if [[ -z "$HEALTH_ENDPOINT" ]]; then
  err "El endpoint no puede estar vacío."
  exit 1
fi

if [[ ! "$HEALTH_ENDPOINT" =~ ^https?:// ]]; then
  err "La URL debe comenzar con http:// o https://"
  exit 1
fi

# Guardar en config.env
update_config_value "BACKEND_HEALTH_ENDPOINT" "$HEALTH_ENDPOINT"
ok "BACKEND_HEALTH_ENDPOINT guardado en $CONFIG_FILE"

# Validar que responde
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_ENDPOINT" || true)"
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Validación OK (HTTP 200): $HEALTH_ENDPOINT"
else
  log "Validación: HTTP $HTTP_CODE en $HEALTH_ENDPOINT (puede ser normal si el backend no está corriendo)"
fi

log "Listo."
