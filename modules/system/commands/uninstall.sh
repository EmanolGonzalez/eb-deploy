#!/usr/bin/env bash
set -e
# =============================================================================
# modules/system/commands/uninstall.sh — Remove deployment
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/system-common.sh"

remove_if_exists() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf "$path"
    log "Eliminado: $path"
  fi
}

require_root

divider
echo "  DESINSTALAR APLICACION"
divider
warn "ESTA ACCION ES IRREVERSIBLE."
warn "Se detendran los servicios y se borraran los binarios y configuraciones."
warn "La configuracion y binarios de la aplicacion seran eliminados."
echo

# M4: una sola opcion de cancelacion + la destructiva (antes habia dos cancelaciones
# redundantes). La destructiva sigue siendo la ultima opcion.
menu_select "Confirmar desinstalacion:" \
  "Cancelar (no hacer nada)" \
  "CONFIRMAR DESINSTALACION (ELIMINAR BINARIOS Y SERVICIOS)"

if [[ "$MENU_SELECTION" != "CONFIRMAR DESINSTALACION (ELIMINAR BINARIOS Y SERVICIOS)" ]]; then
  log "Desinstalacion abortada."
  exit 0
fi

if systemctl list-unit-files | grep -q '^backend.service'; then
  log "Deteniendo el servicio backend..."
  systemctl stop backend || true
  systemctl disable backend || true
  remove_if_exists "/etc/systemd/system/backend.service"
  systemctl daemon-reload
  systemctl reset-failed || true
fi

if [[ -L /etc/nginx/sites-enabled/app || -f /etc/nginx/sites-available/app ]]; then
  log "Eliminando el sitio nginx de la app..."
  remove_if_exists "/etc/nginx/sites-enabled/app"
  remove_if_exists "/etc/nginx/sites-available/app"

  if [[ -f /etc/nginx/sites-available/default ]]; then
    ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  fi

  nginx -t || true
  systemctl reload nginx || true
fi

log "Eliminando directorios de despliegue (se preservan las carpetas de evidencia)..."
remove_if_exists "/app/frontend"
remove_if_exists "/app/backend"
remove_if_exists "/app/releases/frontend"
remove_if_exists "/app/releases/backend"

log "Eliminando archivos de config/runtime (excepto datos de evidencia)..."
remove_if_exists "/app/config/config.env"
remove_if_exists "/app/config/storage.conf"
remove_if_exists "/app/config/db-connection.txt"
remove_if_exists "/app/config/backend-health-endpoint.txt"
remove_if_exists "/app/config/nginx-server-name.txt"

if [[ -d "/app/deploy/storage/evidences" ]]; then
  log "Preservado: /app/deploy/storage/evidences"
fi

# Legacy paths (servidores instalados antes del movimiento a /app/deploy/storage/evidences)
if [[ -d "/app/evidence" ]]; then
  log "Preservado (legacy): /app/evidence"
fi

if [[ -d "/app/evidences" ]]; then
  log "Preservado (legacy): /app/evidences"
fi

log "Desinstalacion completada."
