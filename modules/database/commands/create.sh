#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/database/commands/create.sh — Crear la base de datos (si falta)
#
# Crea SOLO la base de datos (vacía). NO crea tablas: el backend aplica las
# migraciones EF automaticamente al arrancar y construye el esquema.
#
# Idempotente: si la base ya existe, no toca nada y lo informa.
# Se usa cuando alguien borro la base y hay que recrearla antes de arrancar.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"
source "$MODULE_DIR/lib/prompt-connection.sh"

prompt_connection || exit 1

# Un backtick dentro del nombre de la base romperia el quoting del identificador
# SQL. Se rechaza en vez de intentar escapar.
if [[ "$CONN_DB" == *'`'* ]]; then
  err "El nombre de la base de datos no puede contener backticks."
  exit 1
fi

echo ""
divider
echo "  CREAR BASE DE DATOS - $CONN_PROVIDER"
divider
echo ""
warn "Motor    : $CONN_PROVIDER"
warn "Server   : $CONN_SERVER"
warn "Database : $CONN_DB"
echo ""

client=""
if command -v mariadb &>/dev/null; then client="mariadb"
elif command -v mysql &>/dev/null; then client="mysql"
else
  err "No se encontro 'mysql' o 'mariadb'."
  exit 1
fi

# Helpers: se conecta SIN base por defecto (la base puede no existir aun), asi
# se puede consultar information_schema y ejecutar CREATE DATABASE.
docker_container=""
docker_container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'maria|mysql' | head -1 || true)"

run_sql() { # <sql>  -> ejecuta sin base por defecto; imprime el resultado crudo
  if [[ -n "$docker_container" ]]; then
    docker exec -i "$docker_container" "$client" -u"$CONN_USER" -p"$CONN_PASS" -N -B -e "$1"
  else
    "$client" --ssl-verify-server-cert=0 -h "$CONN_SERVER" -P "$CONN_PORT" \
      -u"$CONN_USER" -p"$CONN_PASS" -N -B -e "$1"
  fi
}

# ── Existe ya? ───────────────────────────────────────────────────────────────
already="$(run_sql "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${CONN_DB}';" 2>/dev/null || true)"

if [[ -n "$already" ]]; then
  ok "La base de datos ya existe: $CONN_DB"
  log "No se hizo ningun cambio. EF aplica el esquema al arrancar el backend."
  echo ""
  divider
  echo ""
  exit 0
fi

# ── Crear ────────────────────────────────────────────────────────────────────
log "Creando base de datos '$CONN_DB' (utf8mb4 / utf8mb4_unicode_ci)..."
if run_sql "CREATE DATABASE IF NOT EXISTS \`${CONN_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
  ok "Base de datos creada: $CONN_DB"
  log "EF aplicara el esquema (migraciones) al arrancar el backend."
else
  err "No se pudo crear la base de datos '$CONN_DB'."
  err "Verifica que el usuario tenga privilegio para crear bases (CREATE)."
  exit 1
fi

echo ""
divider
echo "  FIN"
divider
echo ""
