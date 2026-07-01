#!/usr/bin/env bash
# =============================================================================
# modules/health/menu.sh — Health module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  APP HEALTH MENU"
  divider
  menu_select "Selecciona una accion:" \
    "Full health check" \
    "Healthcheck backend (soft)" \
    "Healthcheck frontend" \
    "Status del sistema" \
    "Set health endpoint" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Full health check")          bash "$MODULE_DIR/commands/full.sh" ;;
    "Healthcheck backend (soft)") bash "$MODULE_DIR/commands/check.sh" backend --soft ;;
    "Healthcheck frontend")       bash "$MODULE_DIR/commands/check.sh" frontend ;;
    "Status del sistema")         bash "$MODULE_DIR/commands/status.sh" ;;
    "Set health endpoint")        bash "$MODULE_DIR/commands/set-endpoint.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
