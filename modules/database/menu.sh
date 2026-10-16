#!/usr/bin/env bash
# =============================================================================
# modules/database/menu.sh — Database module menu
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
  echo "  DATABASE MENU"
  dev_mode_banner
  divider
  # M1: idioma unificado a espanol. M7: la accion destructiva (Resetear esquema)
  # va al final, separada visualmente, para no quedar contigua a "Ejecutar esquema".
  #
  # Curation: set-developer / run-schema / reset-schema son acciones de
  # desarrollo/riesgo y SOLO se listan con developer mode activo. Los comandos
  # siguen funcionando al invocarlos directo (deploy database run-schema, ...).
  local_options=("Verificar conexion a BD")
  if deploy_dev_mode; then
    local_options+=("Asignar rol Developer")
    local_options+=("Ejecutar esquema de la base de datos")
  fi
  local_options+=("Correr backup ahora")
  if deploy_dev_mode; then
    local_options+=("--- [DESTRUCTIVO] ---")
    local_options+=("Resetear esquema (elimina TODAS las tablas)")
  fi
  local_options+=("Volver al menu principal")

  menu_select "Selecciona una accion:" "${local_options[@]}"

  case "$MENU_SELECTION" in
    "Verificar conexion a BD") bash "$MODULE_DIR/commands/check.sh" ;;
    "Asignar rol Developer") bash "$MODULE_DIR/commands/set-developer.sh" ;;
    "Ejecutar esquema de la base de datos") bash "$MODULE_DIR/commands/run-schema.sh" ;;
    "Correr backup ahora") bash "$MODULE_DIR/commands/backup.sh" ;;
    "--- [DESTRUCTIVO] ---") log "Es un separador, no una accion. Elegi una opcion valida." ;;
    "Resetear esquema (elimina TODAS las tablas)") bash "$MODULE_DIR/commands/reset-schema.sh" ;;
    "Volver al menu principal") exit 0 ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
