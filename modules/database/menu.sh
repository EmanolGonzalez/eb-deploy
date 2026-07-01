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
  menu_select "Selecciona una accion:" \
    "Check DB connection" \
    "Set Developer role" \
    "Seed test data" \
    "Correr esquema de la base de datos" \
    "Reset schema" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Check DB connection") bash "$MODULE_DIR/commands/check.sh" ;;
    "Set Developer role") bash "$MODULE_DIR/commands/set-developer.sh" ;;
    "Seed test data")     bash "$MODULE_DIR/commands/seed-test-data.sh" ;;
    "Correr esquema de la base de datos") bash "$MODULE_DIR/commands/run-schema.sh" ;;
    "Reset schema")       bash "$MODULE_DIR/commands/reset-schema.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
