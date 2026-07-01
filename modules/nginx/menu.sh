#!/usr/bin/env bash
# =============================================================================
# modules/nginx/menu.sh — Nginx module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  NGINX MENU"
  divider
  menu_select "Selecciona una accion:" \
    "Configurar HTTPS interno (cliente / self-signed)" \
    "Configurar HTTPS con Let's Encrypt (dev / SSL gratis)" \
    "Reload Nginx" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Configurar HTTPS interno (cliente / self-signed)")     bash "$MODULE_DIR/commands/configure-https.sh" ;;
    "Configurar HTTPS con Let's Encrypt (dev / SSL gratis)") bash "$MODULE_DIR/commands/configure-letsencrypt.sh" ;;
    "Reload Nginx")             bash "$MODULE_DIR/commands/reload.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
