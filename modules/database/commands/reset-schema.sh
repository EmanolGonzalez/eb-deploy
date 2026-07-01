#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/database/commands/reset-schema.sh — Drop all tables, keep database
# =============================================================================
#
# Use case: Schema is broken / incompatible. Wipe all tables and re-apply
# a fresh schema con: deploy database run-schema
#
# WARNING: This deletes ALL DATA in all tables. Use with extreme caution.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"
source "$MODULE_DIR/lib/prompt-connection.sh"

SQL_DIR="$MODULE_DIR/../../scripts/sql"

echo ""
warn "========================================"
warn "  ATENCION: RESET DE ESQUEMA"
warn "  Esto ELIMINARA TODAS LAS TABLAS"
warn "  y TODOS LOS DATOS de la base de datos."
warn "  La base de datos en si NO se elimina."
warn "========================================"
echo ""

# C1: pedimos la conexion PRIMERO para poder mostrar el destino exacto antes de
# confirmar. Asi el operador confirma viendo a que server/BD va a resetear, en
# vez de escribir 'RESET' a ciegas y recien despues elegir la conexion.
prompt_connection || exit 1

echo ""
warn "Vas a ELIMINAR TODAS LAS TABLAS en este destino:"
warn "  Motor    : $CONN_PROVIDER"
warn "  Server   : $CONN_SERVER"
warn "  Database : $CONN_DB"
echo ""

read -rp "¿Estas ABSOLUTAMENTE seguro? Escribe 'RESET' para confirmar: " confirm_input
if [[ "$confirm_input" != "RESET" ]]; then
  log "Operacion cancelada. No se hizo ningun cambio."
  exit 0
fi

echo ""
divider
echo "  RESET SCHEMA - $CONN_PROVIDER"
divider
echo ""

if $PROVIDER_IS_SQLSERVER; then
  if ! command -v sqlcmd &>/dev/null; then
    err "sqlcmd no disponible."
    exit 1
  fi

  log "Reseteando esquema SQL Server en $CONN_DB..."
  if sqlcmd -C -S "$CONN_SERVER,$CONN_PORT" -U "$CONN_USER" -P "$CONN_PASS" -d "$CONN_DB" -I -i "$SQL_DIR/reset-schema-sqlserver.sql" 2>&1; then
    ok "Esquema reseteado. Todas las tablas eliminadas de '$CONN_DB'."
  else
    err "Error al resetear el esquema."
    exit 1
  fi

else
  client=""
  if command -v mariadb &>/dev/null; then client="mariadb"
  elif command -v mysql &>/dev/null; then client="mysql"
  else
    err "No se encontro 'mysql' o 'mariadb'."
    exit 1
  fi

  log "Reseteando esquema MariaDB en $CONN_DB..."

  # Docker
  docker_container=""
  docker_container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'maria|mysql' | head -1 || true)"
  if [[ -n "$docker_container" ]]; then
    log "Usando contenedor Docker: $docker_container"
    if docker exec -i "$docker_container" "$client" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$SQL_DIR/reset-schema-mariadb.sql" 2>/dev/null; then
      ok "Esquema reseteado. Todas las tablas eliminadas de '$CONN_DB'."
      exit 0
    fi
  fi

  # Directo
  if "$client" --ssl-verify-server-cert=0 -h "$CONN_SERVER" -P "$CONN_PORT" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$SQL_DIR/reset-schema-mariadb.sql"; then
    ok "Esquema reseteado. Todas las tablas eliminadas de '$CONN_DB'."
  else
    err "Error al resetear el esquema."
    exit 1
  fi
fi

echo ""
divider
ok "Reset completado."
divider
echo ""
