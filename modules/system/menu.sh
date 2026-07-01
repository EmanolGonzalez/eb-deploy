#!/usr/bin/env bash
# =============================================================================
# modules/system/menu.sh — System module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  SYSTEM MENU"
  divider
  menu_select "Selecciona una accion:" \
    "Setup server" \
    "Editar config.env" \
    "Uninstall" \
    "Services (backend/nginx)" \
    "Rotar clave RSA" \
    "Rotar PII Hash Key (Busquedas)" \
    "Audit log" \
    "Lint (verificar scripts)" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Setup server")          bash "$MODULE_DIR/commands/setup.sh" ;;
    "Editar config.env")     bash "$MODULE_DIR/commands/edit-config.sh" ;;
    "Uninstall")             bash "$MODULE_DIR/commands/uninstall.sh" ;;
    "Services (backend/nginx)") bash "$MODULE_DIR/commands/services.sh" ;;
    "Rotar clave RSA")       bash "$MODULE_DIR/commands/rotate-pem.sh" ;;
    "Rotar PII Hash Key (Busquedas)") bash "$MODULE_DIR/commands/rotate-pii.sh" ;;
    "Audit log")             bash "$MODULE_DIR/commands/audit.sh" ;;
    "Lint (verificar scripts)") bash "$MODULE_DIR/commands/lint.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
