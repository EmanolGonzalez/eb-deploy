#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/database/commands/set-developer.sh — Asignar rol Desarrollador (R0)
#
# El Email es PII (se guarda encriptado en BD). Buscamos al usuario por
# Email_hash = HMAC-SHA256(email, PiiEncryption__HashKeyBase64). Este script
# computa ese hash, lo inyecta en el SQL y asigna el rol. Pide email +
# parametros de conexion interactivamente.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"
source "$MODULE_DIR/lib/prompt-connection.sh"

SQL_DIR="$MODULE_DIR/../../scripts/sql"

echo ""
divider
echo "  ASIGNAR ROL DESARROLLADOR (R0)"
divider
echo ""

read -rp "Email del usuario: " EMAIL
if [[ -z "$EMAIL" ]]; then
  err "Email requerido."
  exit 1
fi

# =============================================================================
# HASH DE BUSQUEDA PII
# El Email es PII: se busca por Email_hash = HMAC-SHA256(email, HashKey).
# La HashKey vive en config.env (PiiEncryption__HashKeyBase64). Computamos el
# hash aca y lo inyectamos en el SQL reemplazando 0xHASH_PLACEHOLDER.
# OJO: el email debe ser IDENTICO al guardado (sin normalizar) o el hash no matchea.
# =============================================================================
CONFIG_FILE="/app/config/config.env"

compute_email_hash() {
  command -v openssl &>/dev/null || { err "openssl no disponible (necesario para el hash PII)."; exit 1; }

  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "No se encontro $CONFIG_FILE — necesito PiiEncryption__HashKeyBase64 para computar el hash."
    exit 1
  fi

  local hashkey_b64
  hashkey_b64="$(grep -E '^[[:space:]]*PiiEncryption__HashKeyBase64=' "$CONFIG_FILE" | tail -1 | cut -d= -f2-)"
  hashkey_b64="${hashkey_b64%\"}"; hashkey_b64="${hashkey_b64#\"}"   # quitar comillas

  if [[ -z "$hashkey_b64" || "$hashkey_b64" == "CHANGE_ME" ]]; then
    err "PiiEncryption__HashKeyBase64 no esta configurada en $CONFIG_FILE."
    exit 1
  fi

  local key_hex
  key_hex="$(printf '%s' "$hashkey_b64" | base64 -d 2>/dev/null | od -An -v -tx1 | tr -d ' \n')"
  if [[ -z "$key_hex" ]]; then
    err "No se pudo decodificar PiiEncryption__HashKeyBase64 (base64 invalido?)."
    exit 1
  fi

  EMAIL_HASH_HEX="$(printf '%s' "$EMAIL" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$key_hex" | sed 's/^.*= *//')"
  if [[ ! "$EMAIL_HASH_HEX" =~ ^[0-9a-f]{64}$ ]]; then
    err "El hash computado no es valido (esperaba 64 hex chars): '$EMAIL_HASH_HEX'"
    exit 1
  fi
}

compute_email_hash

prompt_connection || exit 1

echo ""
divider
echo "  ASIGNANDO ROL DESARROLLADOR"
echo "  Email   : $EMAIL"
echo "  Hash    : 0x$EMAIL_HASH_HEX"
echo "  Server  : $CONN_SERVER"
echo "  DB      : $CONN_DB"
divider
echo ""
warn "Si dice 'usuario no encontrado': el email debe ser IDENTICO al guardado"
warn "(sin normalizar mayus/minus ni espacios) o el hash no matchea. Verifica tambien"
warn "que PiiEncryption__HashKeyBase64 sea la MISMA con la que el backend guardo los datos."
echo ""

if $PROVIDER_IS_SQLSERVER; then
  if ! command -v sqlcmd &>/dev/null; then
    err "sqlcmd no disponible."
    exit 1
  fi

  temp_sql="$(mktemp)"
  sed "s/0xHASH_PLACEHOLDER/0x${EMAIL_HASH_HEX}/" "$SQL_DIR/set-developer-sqlserver.sql" > "$temp_sql"

  # -C: confiar en el cert del server (servers internos sin SSL valido).
  if sqlcmd -C -S "$CONN_SERVER,$CONN_PORT" -U "$CONN_USER" -P "$CONN_PASS" -d "$CONN_DB" -I -i "$temp_sql"; then
    ok "Rol Desarrollador asignado a '$EMAIL' en SQL Server."
  else
    err "Error al asignar rol en SQL Server."
    rm -f "$temp_sql"
    exit 1
  fi
  rm -f "$temp_sql"

else
  client=""
  if command -v mariadb &>/dev/null; then client="mariadb"
  elif command -v mysql &>/dev/null; then client="mysql"
  else
    err "No se encontro 'mysql' o 'mariadb'."
    exit 1
  fi

  temp_sql="$(mktemp)"
  sed "s/0xHASH_PLACEHOLDER/0x${EMAIL_HASH_HEX}/" "$SQL_DIR/set-developer-mariadb.sql" > "$temp_sql"

  # Docker
  docker_container=""
  docker_container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'maria|mysql' | head -1 || true)"
  if [[ -n "$docker_container" ]]; then
    log "Usando contenedor Docker: $docker_container"
    if docker exec -i "$docker_container" "$client" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$temp_sql" 2>/dev/null; then
      ok "Rol Desarrollador asignado a '$EMAIL' en MariaDB (via Docker)."
      rm -f "$temp_sql"
      exit 0
    fi
  fi

  # Directo
  if "$client" --ssl-verify-server-cert=0 -h "$CONN_SERVER" -P "$CONN_PORT" -u"$CONN_USER" -p"$CONN_PASS" "$CONN_DB" < "$temp_sql"; then
    ok "Rol Desarrollador asignado a '$EMAIL' en MariaDB."
  else
    err "Error al asignar rol en MariaDB."
    rm -f "$temp_sql"
    exit 1
  fi
  rm -f "$temp_sql"
fi

echo ""
divider
echo "  FIN"
divider
echo ""
