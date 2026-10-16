#!/usr/bin/env bash
# =============================================================================
# modules/nginx/menu.sh — Nginx module menu
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
  echo "  NGINX MENU"
  dev_mode_banner
  divider
  # Curation: Let's Encrypt es dev-only (el cliente usa cert interno). Solo se
  # lista con developer mode activo; el comando sigue funcionando directo.
  local_options=("Configurar HTTPS interno (cliente / self-signed)")
  if deploy_dev_mode; then
    local_options+=("Configurar HTTPS con Let's Encrypt (dev / SSL gratis)")
  fi
  local_options+=("Reload Nginx")
  local_options+=("Volver al menu principal")

  menu_select "Selecciona una accion:" "${local_options[@]}"

  case "$MENU_SELECTION" in
    "Configurar HTTPS interno (cliente / self-signed)")     bash "$MODULE_DIR/commands/configure-https.sh" ;;
    "Configurar HTTPS con Let's Encrypt (dev / SSL gratis)") bash "$MODULE_DIR/commands/configure-letsencrypt.sh" ;;
    "Reload Nginx")             bash "$MODULE_DIR/commands/reload.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
