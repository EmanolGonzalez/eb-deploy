#!/usr/bin/env bash
# =============================================================================
# modules/database/lib/prompt-connection.sh
#
# Helper compartido para pedir parámetros de conexión a BD interactivamente.
#
# Define:
#   prompt_connection()     -> pide provider + server + port + db + user + pass
#   CONN_PROVIDER, CONN_SERVER, CONN_PORT, CONN_DB, CONN_USER, CONN_PASS
#   PROVIDER_IS_SQLSERVER, PROVIDER_IS_MARIADB (true/false)
#
# Uso:
#   source "$MODULE_DIR/lib/prompt-connection.sh"
#   prompt_connection || exit 1
#   echo "Conectando a $CONN_PROVIDER: $CONN_SERVER..."
# =============================================================================

# Self-contained: resolve paths relative to this file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../core/logger.sh"
source "$SCRIPT_DIR/../../../core/input.sh"

prompt_connection() {
  # Resetear variables
  CONN_PROVIDER=""
  CONN_SERVER=""
  CONN_PORT=""
  CONN_DB=""
  CONN_USER=""
  CONN_PASS=""
  PROVIDER_IS_SQLSERVER=false
  PROVIDER_IS_MARIADB=false

  echo ""

  # --- Provider ---
  menu_select "Motor de base de datos:" "SqlServer" "MariaDB" "Salir"
  CONN_PROVIDER="$MENU_SELECTION"
  [[ "$CONN_PROVIDER" == "Salir" ]] && return 1

  if [[ "$CONN_PROVIDER" == "SqlServer" ]]; then
    PROVIDER_IS_SQLSERVER=true
    DEFAULT_PORT="1433"
  else
    PROVIDER_IS_MARIADB=true
    DEFAULT_PORT="3307"
  fi

  # --- Parámetros ---
  echo ""
  log "=== $CONN_PROVIDER - Parametros de conexion ==="
  echo ""

  read -rp "Server (ej: localhost, 192.168.1.100): " CONN_SERVER
  read -rp "Port [$DEFAULT_PORT]: " CONN_PORT
  CONN_PORT="${CONN_PORT:-$DEFAULT_PORT}"

  read -rp "Database: " CONN_DB
  read -rp "User: " CONN_USER
  echo -n "Password: "
  CONN_PASS=""
  while IFS= read -r -s -n1 char; do
    [[ -z "$char" ]] && break  # Enter termina
    if [[ "$char" == $'\x7f' ]]; then  # Backspace
      [[ -n "$CONN_PASS" ]] && CONN_PASS="${CONN_PASS%?}" && echo -en "\b \b"
    else
      CONN_PASS+="$char"
      echo -n "*"
    fi
  done
  echo ""
  echo ""

  # --- Validación ---
  if [[ -z "$CONN_SERVER" || -z "$CONN_DB" || -z "$CONN_USER" ]]; then
    err "Server, Database y User son requeridos."
    return 1
  fi

  return 0
}
