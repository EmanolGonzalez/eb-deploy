#!/usr/bin/env bash
# =============================================================================
# modules/release/menu.sh — Release module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  RELEASE MENU"
  divider
  menu_select "Selecciona una accion:" \
    "Build component" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Build component") bash "$MODULE_DIR/commands/build.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
