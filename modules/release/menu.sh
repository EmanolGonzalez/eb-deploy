#!/usr/bin/env bash
# =============================================================================
# modules/release/menu.sh — Release module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"
source "$MODULE_DIR/../../core/devmode.sh" 2>/dev/null || {
  deploy_dev_mode() { [[ "${DEPLOY_DEV_MODE:-}" == "1" ]]; }
  dev_mode_banner() { deploy_dev_mode && echo "*** MODO DESARROLLADOR ACTIVO ***" || true; }
}

while true; do
  echo
  divider
  echo "  RELEASE MENU"
  dev_mode_banner
  divider
  menu_select "Selecciona una accion:" \
    "Construir componente" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Construir componente") bash "$MODULE_DIR/commands/build.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
