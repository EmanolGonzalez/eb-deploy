#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/system/commands/services.sh — Manage services
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/system-common.sh"

# M6: verificacion defensiva. Este comando depende de que system-common.sh haya
# sourceado core/input.sh (menu_select) y core/logger.sh (err). Si por un cambio
# de paths eso fallara, damos un error claro en vez de "command not found".
if ! declare -f menu_select >/dev/null; then
  echo "ERR  menu_select no disponible: revisa que $MODULE_DIR/lib/system-common.sh sourcee core/input.sh." >&2
  exit 1
fi

menu_select "Selecciona servicio:" "backend" "nginx"
SERVICE="$MENU_SELECTION"

menu_select "Selecciona accion:" "status" "start" "stop" "restart" "logs"

case "$MENU_SELECTION" in
  "status")
    systemctl status "$SERVICE" --no-pager
    ;;
  "start")
    start_service "$SERVICE"
    ;;
  "stop")
    stop_service "$SERVICE"
    ;;
  "restart")
    restart_service "$SERVICE"
    ;;
  "logs")
    # C2: journalctl -f sigue en vivo. Avisamos como salir para que el operador
    # no quede "atrapado". El '|| true' evita que el exit 130 del Ctrl+C aborte
    # el script por set -euo pipefail.
    log "Mostrando logs en tiempo real. Presiona Ctrl+C para salir."
    journalctl -u "$SERVICE" -f || true
    ;;
esac
