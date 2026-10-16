#!/usr/bin/env bash
# =============================================================================
# modules/health/menu.sh — Health module menu
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
  echo "  APP HEALTH MENU"
  dev_mode_banner
  divider
  # La vista simple va PRIMERO ("recomendado"): es lo que el operador corre en
  # un toque. El resto son comandos tecnicos de diagnostico, agrupados abajo.
  menu_select "Selecciona una accion:" \
    "Ver estado del sistema (recomendado)" \
    "--- [DIAGNOSTICO TECNICO] ---" \
    "Diagnostico: Full health check" \
    "Diagnostico: Healthcheck backend (soft)" \
    "Diagnostico: Healthcheck frontend" \
    "Diagnostico: Status del sistema" \
    "Diagnostico: Set health endpoint" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Ver estado del sistema (recomendado)") bash "$MODULE_DIR/commands/simple.sh" ;;
    "--- [DIAGNOSTICO TECNICO] ---") log "Es un separador, no una accion. Elegi una opcion valida." ;;
    "Diagnostico: Full health check")          bash "$MODULE_DIR/commands/full.sh" ;;
    "Diagnostico: Healthcheck backend (soft)") bash "$MODULE_DIR/commands/check.sh" backend --soft ;;
    "Diagnostico: Healthcheck frontend")       bash "$MODULE_DIR/commands/check.sh" frontend ;;
    "Diagnostico: Status del sistema")         bash "$MODULE_DIR/commands/status.sh" ;;
    "Diagnostico: Set health endpoint")        bash "$MODULE_DIR/commands/set-endpoint.sh" ;;
    "Volver al menu principal") exit 0 ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
