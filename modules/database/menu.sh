#!/usr/bin/env bash
# =============================================================================
# modules/database/menu.sh — Database module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  DATABASE MENU"
  divider
  # M1: idioma unificado a espanol. M7: la accion destructiva (Resetear esquema)
  # va al final, separada visualmente, para no quedar contigua a "Ejecutar esquema".
  menu_select "Selecciona una accion:" \
    "Verificar conexion a BD" \
    "Asignar rol Developer" \
    "Ejecutar esquema de la base de datos" \
    "Correr backup ahora" \
    "--- [DESTRUCTIVO] ---" \
    "Resetear esquema (elimina TODAS las tablas)" \
    "Volver al menu principal"

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
