#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/database/commands/run-schema.sh — Ejecutar esquema de base de datos
#
# Elige el archivo .sql segun el provider:
#   MariaDB  -> scripts/sql/esquema-backend.mariadb.sql
#   SqlServer -> scripts/sql/esquema-backend.sqlserver.sql
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"
source "$MODULE_DIR/lib/prompt-connection.sh"

prompt_connection || exit 1

if $PROVIDER_IS_SQLSERVER; then
  SQL_FILE="$MODULE_DIR/../../scripts/sql/esquema-backend.sqlserver.sql"
else
  SQL_FILE="$MODULE_DIR/../../scripts/sql/esquema-backend.mariadb.sql"
fi

if [[ ! -f "$SQL_FILE" ]]; then
  err "No se encontro: $SQL_FILE"
  err "Crea el archivo con el esquema correspondiente antes de ejecutar."
  exit 1
fi

echo ""
divider
echo "  CORRER ESQUEMA - $(basename "$SQL_FILE") ($(wc -l < "$SQL_FILE") lineas)"
divider
echo ""

warn "Archivo: $(basename "$SQL_FILE")"
warn "Server  : $CONN_SERVER ($CONN_PROVIDER)"
warn "DB      : $CONN_DB"
echo ""
warn "=================================================================="
warn "  CUIDADO — CONFLICTO CON LAS MIGRACIONES EF"
warn "  El backend aplica migraciones EF automaticas al arrancar y se"
warn "  guia por la tabla __EFMigrationsHistory."
warn ""
warn "  Correr este esquema SQL sobre una BD que el backend va a migrar"
warn "  DESINCRONIZA el historial -> el backend entra en crash-loop con"
warn "  'Duplicate column' (esquema fisico adelantado vs historial)."
warn ""
warn "  Elegi UNA sola fuente de verdad del esquema:"
warn "    - EF auto-migrate (recomendado): NO uses run-schema; arranca el"
warn "      backend sobre una BD VACIA (deploy database reset-schema)."
warn "    - Esquema SQL: solo si el backend NO auto-migra."
warn "=================================================================="
echo ""
if ! confirm "Entiendo el riesgo y quiero ejecutar el esquema SQL igual?"; then
  warn "Operacion cancelada."
  exit 0
fi

echo ""
divider
echo "  EJECUTANDO $(basename "$SQL_FILE")"
divider
echo ""

# Normalizacion del esquema — SIEMPRE (no solo si hay UTF-16). Cubre:
#   - Encoding: saca nulos (UTF-16) y BOM (UTF-16/UTF-8) y CR (CRLF).
#   - Collations de versiones nuevas -> general_ci (compat con servers viejos).
#   - DEFAULT utc_timestamp(N) PELADO -> envuelto en parentesis. mariadb-dump lo
#     muestra sin parentesis, pero MySQL 8 y MariaDB lo RECHAZAN como default;
#     necesita "DEFAULT (utc_timestamp(N))" (default por expresion, 10.2+/8.0.13+).
#     Mantiene UTC, consistente con la migracion EF que usa (UTC_TIMESTAMP(6)).
log "Normalizando esquema (encoding + sintaxis compatible)..."
tmp_clean=$(mktemp)
tr -d '\000' < "$SQL_FILE" | \
  sed '1s/^\xff\xfe//; 1s/^\xfe\xff//; 1s/^\xef\xbb\xbf//' | \
  sed 's/utf8mb4_uca1400_ai_ci/utf8mb4_general_ci/g' | \
  sed 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g' | \
  sed -E 's/DEFAULT[[:space:]]+utc_timestamp\(([0-9]*)\)/DEFAULT (utc_timestamp(\1))/Ig' | \
  tr -d '\r' > "$tmp_clean"
SQL_EXEC_PATH="$tmp_clean"

exitcode=0
if $PROVIDER_IS_SQLSERVER; then
  if ! command -v sqlcmd &>/dev/null; then
    err "sqlcmd no disponible."
    [[ "$SQL_EXEC_PATH" == "/tmp/"* ]] && rm -f "$SQL_EXEC_PATH"
    exit 1
  fi
  # -C: confiar en el cert del server (servers internos sin SSL valido).
  sqlcmd -C -S "$CONN_SERVER,$CONN_PORT" -d "$CONN_DB" -U "$CONN_USER" -P "$CONN_PASS" -I -i "$SQL_EXEC_PATH"
  exitcode=$?
else
  client=""
  if command -v mariadb &>/dev/null; then client="mariadb"
  elif command -v mysql &>/dev/null; then client="mysql"
  else
    err "No se encontro 'mariadb' ni 'mysql'."
    [[ "$SQL_EXEC_PATH" == "/tmp/"* ]] && rm -f "$SQL_EXEC_PATH"
    exit 1
  fi

  docker_container=""
  docker_container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'maria|mysql' | head -1 || true)"
  if [[ -n "$docker_container" ]]; then
    log "Usando contenedor Docker: $docker_container"
    docker exec -i "$docker_container" "$client" --binary-mode -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$SQL_EXEC_PATH"
    exitcode=$?
  else
    "$client" --binary-mode --ssl-verify-server-cert=0 -h "$CONN_SERVER" -P "$CONN_PORT" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$SQL_EXEC_PATH"
    exitcode=$?
  fi
fi

# Limpiar temporal si se creo
[[ "$SQL_EXEC_PATH" == "/tmp/"* ]] && rm -f "$SQL_EXEC_PATH"

echo ""
if [[ $exitcode -eq 0 ]]; then
  ok "Esquema ejecutado exitosamente."
else
  err "La ejecucion fallo con codigo $exitcode."
  exit $exitcode
fi

echo ""
divider
echo "  FIN"
divider
echo ""
