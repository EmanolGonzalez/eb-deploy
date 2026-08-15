#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/database/commands/seed-test-data.sh — Insertar datos de prueba y
#   validar permisos de escritura (INSERT, SELECT, UPDATE, DELETE)
#
# Pide los parametros de conexion interactivamente.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"
source "$MODULE_DIR/lib/prompt-connection.sh"

SQL_DIR="$MODULE_DIR/../../scripts/sql"

# =============================================================================
# UUID GENERATION
# =============================================================================
generate_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    echo "$(date +%s%N)-$$-$RANDOM" | md5sum 2>/dev/null | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\).*/\1-\2-\3-\4-\5/' || \
    echo "fallback-$(date +%s)-$$"
  fi
}

# =============================================================================
# BUILD SQL FROM TEMPLATE
# =============================================================================
generate_test_data() {
  ORG_ID="$(generate_uuid)"
  OFFICE_ID="$(generate_uuid)"
  USER_ID="$(generate_uuid)"
  ORDER_ID="$(generate_uuid)"

  ORG_CODIGO="ORG-TEST-${ORG_ID:0:8}"
  ORG_NOMBRE="Organizacion de Prueba Seed"
  OFFICE_CODIGO="OFF-TEST-${OFFICE_ID:0:8}"
  OFFICE_NOMBRE="Oficina de Prueba Seed"
  OFFICE_DIRECCION="Direccion de prueba"
  OFFICE_PROVINCIA="Provincia Test"
  OFFICE_DISTRITO="Distrito Test"
  OFFICE_CORREGIMIENTO="Corregimiento Test"
  USER_USERNAME="testuser-${USER_ID:0:8}"
  USER_EMAIL="test-${USER_ID:0:8}@prueba.com"
  USER_NOMBRES="Usuario"
  USER_APELLIDOS="De Prueba"
  USER_TELEFONO="600000000"
  USER_DOCUMENTO="PE-00000000-A"
  REF_CODE="REF-${ORDER_ID:0:8}"
  ORDER_NACIONALIDAD="Panamena"
  ORDER_DIRECCION="Direccion de prueba"
  ORDER_PROVINCIA="Provincia Test"
  ORDER_DESCRIPCION="Orden de prueba - validacion de permisos"
  ORDER_SEXO="M"
  ORDER_RANGOEDAD="30-40"
}

build_sql() {
  local template="$1"
  local temp_sql
  temp_sql="$(mktemp)"

  sed \
    -e "s|__ORG_ID__|${ORG_ID}|g" \
    -e "s|__OFFICE_ID__|${OFFICE_ID}|g" \
    -e "s|__USER_ID__|${USER_ID}|g" \
    -e "s|__ORDER_ID__|${ORDER_ID}|g" \
    -e "s|__ORG_CODIGO__|${ORG_CODIGO}|g" \
    -e "s|__ORG_NOMBRE__|${ORG_NOMBRE}|g" \
    -e "s|__OFFICE_CODIGO__|${OFFICE_CODIGO}|g" \
    -e "s|__OFFICE_NOMBRE__|${OFFICE_NOMBRE}|g" \
    -e "s|__OFFICE_DIRECCION__|${OFFICE_DIRECCION}|g" \
    -e "s|__OFFICE_PROVINCIA__|${OFFICE_PROVINCIA}|g" \
    -e "s|__OFFICE_DISTRITO__|${OFFICE_DISTRITO}|g" \
    -e "s|__OFFICE_CORREGIMIENTO__|${OFFICE_CORREGIMIENTO}|g" \
    -e "s|__USER_USERNAME__|${USER_USERNAME}|g" \
    -e "s|__USER_EMAIL__|${USER_EMAIL}|g" \
    -e "s|__USER_NOMBRES__|${USER_NOMBRES}|g" \
    -e "s|__USER_APELLIDOS__|${USER_APELLIDOS}|g" \
    -e "s|__USER_TELEFONO__|${USER_TELEFONO}|g" \
    -e "s|__USER_DOCUMENTO__|${USER_DOCUMENTO}|g" \
    -e "s|__REF_CODE__|${REF_CODE}|g" \
    -e "s|__ORDER_NACIONALIDAD__|${ORDER_NACIONALIDAD}|g" \
    -e "s|__ORDER_DIRECCION__|${ORDER_DIRECCION}|g" \
    -e "s|__ORDER_PROVINCIA__|${ORDER_PROVINCIA}|g" \
    -e "s|__ORDER_DESCRIPCION__|${ORDER_DESCRIPCION}|g" \
    -e "s|__ORDER_SEXO__|${ORDER_SEXO}|g" \
    -e "s|__ORDER_RANGOEDAD__|${ORDER_RANGOEDAD}|g" \
    "$template" > "$temp_sql"

  echo "$temp_sql"
}

# =============================================================================
# RUN: MariaDB
# =============================================================================
run_mariadb() {
  log "Ejecutando seed en MariaDB: $CONN_SERVER:$CONN_PORT, db=$CONN_DB"

  generate_test_data
  local temp_sql
  temp_sql="$(build_sql "$SQL_DIR/seed-test-data-mariadb.sql")"

  local client=""
  if command -v mariadb &>/dev/null; then client="mariadb"
  elif command -v mysql &>/dev/null; then client="mysql"
  else
    err "No se encontro 'mariadb' ni 'mysql'."
    rm -f "$temp_sql"
    return 1
  fi

  # Docker primero
  local docker_container=""
  docker_container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'maria|mysql' | head -1 || true)"
  if [[ -n "$docker_container" ]]; then
    log "Usando contenedor Docker: $docker_container"
    if docker exec -i "$docker_container" "$client" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$temp_sql" 2>/dev/null; then
      rm -f "$temp_sql"
      ok "MariaDB: Seed completado exitosamente (via Docker)"
      echo ""
      return 0
    fi
  fi

  # Directo
  "$client" --ssl-verify-server-cert=0 -h "$CONN_SERVER" -P "$CONN_PORT" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$temp_sql"
  local exitcode=$?
  rm -f "$temp_sql"

  if [[ $exitcode -eq 0 ]]; then
    ok "MariaDB: Seed completado exitosamente"
    echo ""
  fi

  return $exitcode
}

# =============================================================================
# MAIN
# =============================================================================
echo ""
divider
echo "  SEED TEST DATA - Validar permisos de escritura"
divider
echo ""

warn "ESTA OPERACION INSERTARA datos de prueba en las tablas:"
echo "  - organizations, offices, users, orders"
echo ""
echo "Prueba: INSERT, SELECT, UPDATE (con restore), DELETE (con re-insert)"
echo "Al finalizar, los datos se eliminan automaticamente."
echo ""
if ! confirm "Continuar?"; then
  warn "Operacion cancelada."
  exit 0
fi

prompt_connection || exit 1

echo ""
divider
echo "  EJECUTANDO SEED EN $CONN_PROVIDER"
divider
echo ""

run_mariadb || {
  err "MariaDB: Fallo en operaciones de escritura."
  echo ""
  warn "POSIBLES CAUSAS:"
  echo "  - El usuario no tiene permisos INSERT/UPDATE/DELETE en las tablas"
  echo "  - La conexion esta bloqueada por firewall"
  echo "  - El servidor no esta accesible desde aqui"
  exit 1
}

echo ""
divider
ok "TEST DE PERMISOS DE ESCRITURA COMPLETADO"
echo ""
echo "  INSERT  ✅  SELECT  ✅  UPDATE  ✅  DELETE  ✅"
echo ""
info "Los datos de prueba fueron automaticamente eliminados."
divider
echo ""
