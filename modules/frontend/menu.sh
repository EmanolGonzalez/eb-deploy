#!/usr/bin/env bash
# =============================================================================
# modules/frontend/menu.sh — Frontend module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  FRONTEND MENU"
  divider
  menu_select "Selecciona una accion:" \
    "Install (desde /app/artifacts/frontend.rar)" \
    "Update (cambiar version local)" \
    "Rollback (volver una version atras)" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Install (desde /app/artifacts/frontend.rar)") bash "$MODULE_DIR/commands/install.sh" ;;
    "Update (cambiar version local)")              bash "$MODULE_DIR/commands/update.sh" ;;
    "Rollback (volver una version atras)")         bash "$MODULE_DIR/commands/rollback.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
