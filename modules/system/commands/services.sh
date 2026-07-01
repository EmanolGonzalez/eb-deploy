#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/system/commands/services.sh — Manage services
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/system-common.sh"

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
    journalctl -u "$SERVICE" -f
    ;;
esac
