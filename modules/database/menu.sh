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
  # Este modulo NO tiene acciones gateadas por developer mode: todas son
  # operaciones soportadas del operador.
  #   - create: recrea la base si alguien la borro (EF migra al arrancar).
  #   - reset-schema: reset de emergencia (borra tablas, conserva la base).
  #   - set-developer: forma soportada de otorgar el nivel administrativo maximo.
  #   - backup: si no esta configurado, lo configura (passphrase + timer cada
  #     3 dias); si ya lo esta, LISTA los respaldos existentes.
  menu_select "Selecciona una accion:" \
    "Respaldos (configurar / ver los existentes)" \
    "Crear base de datos (si fue eliminada)" \
    "Verificar conexion a BD" \
    "Reset de esquema (borra tablas, conserva la base)" \
    "Asignar rol Developer" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Respaldos (configurar / ver los existentes)")        bash "$MODULE_DIR/commands/backup.sh" ;;
    "Crear base de datos (si fue eliminada)")             bash "$MODULE_DIR/commands/create.sh" ;;
    "Verificar conexion a BD")                            bash "$MODULE_DIR/commands/check.sh" ;;
    "Reset de esquema (borra tablas, conserva la base)")  bash "$MODULE_DIR/commands/reset-schema.sh" ;;
    "Asignar rol Developer")                              bash "$MODULE_DIR/commands/set-developer.sh" ;;
    "Volver al menu principal") exit 0 ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
