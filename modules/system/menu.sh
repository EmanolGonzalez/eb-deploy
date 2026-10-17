#!/usr/bin/env bash
# =============================================================================
# modules/system/menu.sh — System module menu
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
  echo "  SYSTEM MENU"
  dev_mode_banner
  divider
  # Curation: Uninstall es una accion de riesgo y SOLO se lista con developer
  # mode activo; el comando sigue funcionando directo (deploy system uninstall).
  local_options=("Setup server")
  local_options+=("Editar config.env")
  if deploy_dev_mode; then
    local_options+=("Uninstall")
  fi
  local_options+=("Services (backend/nginx)")
  local_options+=("Rotar clave RSA")
  local_options+=("Rotar PII Hash Key (Busquedas)")
  local_options+=("Audit log")
  local_options+=("Lint (verificar scripts)")
  local_options+=("Volver al menu principal")

  menu_select "Selecciona una accion:" "${local_options[@]}"

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
