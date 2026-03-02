#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# check-db.sh — Diagnóstico de conectividad con la base de datos SQL Server
#
# Verifica en orden:
#   1. Resolución DNS del host
#   2. Conectividad TCP al puerto
#   3. Autenticación SQL (si sqlcmd está disponible)
#
# Funciona en Linux (servidor) y Windows Git Bash (máquina de desarrollo).
#
# Uso:
#   bash check-db.sh
#   bash check-db.sh "Server=sql.host;Database=EB;User ID=sa;Password=secret;"
#
# En Linux lee DB_CONNECTION_STRING de /app/config/config.env si existe.
# =============================================================================

CONFIG_FILE="/app/config/config.env"

log()  { echo -e "\033[1;34m==> $*\033[0m"; }
err()  { echo -e "\033[1;31mERR  $*\033[0m" >&2; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }
step() { echo; echo -e "\033[1;37m--- $* ---\033[0m"; }

# ── DETECCIÓN DE SO ────────────────────────────────────────────────────────────

OS_TYPE="unknown"

detect_os() {
  local kernel
  kernel="$(uname -s 2>/dev/null || echo "unknown")"
  case "$kernel" in
    Linux)                OS_TYPE="linux"   ;;
    MINGW*|MSYS*|CYGWIN*) OS_TYPE="windows" ;;
    *)                    OS_TYPE="unknown" ;;
  esac
  log "Sistema detectado: $OS_TYPE (uname: $kernel)"
}

# ── ROOT (solo Linux) ──────────────────────────────────────────────────────────

conditional_require_root() {
  if [[ "$OS_TYPE" == "linux" ]] && [[ "$EUID" -ne 0 ]]; then
    err "En Linux este script debe ejecutarse como root (necesario para leer config.env)."
    err "Usa: sudo bash check-db.sh"
    exit 1
  fi
}

# ── OBTENER CONNECTION STRING ──────────────────────────────────────────────────

CONNECTION_STRING=""

load_connection_string() {
  # Prioridad 1: argumento de línea de comandos
  if [[ -n "${1:-}" ]]; then
    CONNECTION_STRING="$1"
    log "Connection string recibido como argumento."
    return
  fi

  # Prioridad 2: config.env (solo Linux)
  if [[ "$OS_TYPE" == "linux" ]] && [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
      CONNECTION_STRING="$DB_CONNECTION_STRING"
      log "Connection string cargado desde $CONFIG_FILE"
      return
    else
      warn "config.env encontrado pero DB_CONNECTION_STRING está vacío."
    fi
  fi

  # Prioridad 3: input interactivo (oculto)
  echo
  read -rsp "Connection string (input oculto): " CONNECTION_STRING
  echo
  if [[ -z "$CONNECTION_STRING" ]]; then
    err "El connection string es obligatorio."
    exit 1
  fi
}

# ── PARSEO DEL CONNECTION STRING ───────────────────────────────────────────────

DB_HOST=""
DB_PORT="1433"
DB_NAME=""
DB_USER=""
DB_PASS=""

parse_connection_string() {
  local cs="$1"

  # Extraer valor de Server= (case-insensitive)
  local raw_server
  raw_server="$(printf '%s' "$cs" | sed -nE 's/.*[Ss]erver=([^;]+).*/\1/p')"

  # Quitar prefijo tcp: si existe
  raw_server="${raw_server#tcp:}"
  raw_server="${raw_server#TCP:}"
  raw_server="${raw_server// /}"  # quitar espacios

  if [[ -z "$raw_server" ]]; then
    err "No se pudo extraer 'Server' del connection string."
    err "Formato esperado: Server=host,puerto  o  Server=host"
    exit 1
  fi

  # SQL Server usa coma para separar host y puerto: host,1433
  if [[ "$raw_server" == *,* ]]; then
    DB_HOST="${raw_server%%,*}"
    DB_PORT="${raw_server##*,}"
  else
    DB_HOST="$raw_server"
    DB_PORT="1433"
  fi

  if ! [[ "$DB_PORT" =~ ^[0-9]+$ ]]; then
    err "Puerto inválido extraído del connection string: '$DB_PORT'"
    exit 1
  fi

  DB_NAME="$(printf '%s' "$cs" | sed -nE 's/.*([Dd]atabase|[Ii]nitial [Cc]atalog)=([^;]+).*/\2/p')"
  DB_USER="$(printf '%s' "$cs" | sed -nE 's/.*([Uu]ser [Ii][Dd]|[Uu]id)=([^;]+).*/\2/p')"
  DB_PASS="$(printf '%s' "$cs" | sed -nE 's/.*[Pp]assword=([^;]+).*/\1/p')"
}

print_parsed_summary() {
  echo
  echo "========================================"
  echo "  Parámetros detectados"
  echo "========================================"
  printf "  Host     : %s\n" "$DB_HOST"
  printf "  Puerto   : %s\n" "$DB_PORT"
  printf "  Database : %s\n" "${DB_NAME:-(no especificada)}"
  printf "  Usuario  : %s\n" "${DB_USER:-(no especificado — ¿Trusted Connection?)}"
  if [[ -n "${DB_PASS:-}" ]]; then
    printf "  Password : %s\n" "(configurado, oculto)"
  else
    printf "  Password : %s\n" "(no especificado)"
  fi
  echo "========================================"
}

# ── TEST 1: DNS ────────────────────────────────────────────────────────────────

check_dns() {
  log "Resolviendo hostname '$DB_HOST'..."

  if command -v getent &>/dev/null; then
    if getent hosts "$DB_HOST" &>/dev/null; then
      ok "DNS: '$DB_HOST' resuelve correctamente."
      return 0
    fi
  elif nslookup "$DB_HOST" &>/dev/null 2>&1; then
    ok "DNS: '$DB_HOST' resuelve correctamente (via nslookup)."
    return 0
  fi

  err "DNS: no se pudo resolver '$DB_HOST'."
  err "     Verifica: nombre del host, DNS del servidor, y /etc/hosts."
  return 1
}

# ── TEST 2: TCP ────────────────────────────────────────────────────────────────

check_tcp() {
  log "Probando conectividad TCP a '$DB_HOST:$DB_PORT'..."

  if ! command -v timeout &>/dev/null; then
    warn "'timeout' no encontrado — el test TCP puede bloquearse si el host no responde."
  fi

  local connected=false

  if command -v timeout &>/dev/null; then
    if timeout 5 bash -c "echo >/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
      connected=true
    fi
  else
    # Fallback sin timeout
    if (echo >/dev/tcp/"${DB_HOST}"/"${DB_PORT}") 2>/dev/null; then
      connected=true
    fi
  fi

  if [[ "$connected" == true ]]; then
    ok "TCP: puerto $DB_PORT accesible en '$DB_HOST'."
    return 0
  else
    err "TCP: no se pudo conectar a '$DB_HOST:$DB_PORT'."
    err "     Verifica: servicio SQL Server activo, firewall, y puerto correcto."
    return 1
  fi
}

# ── TEST 3: AUTENTICACIÓN SQL ──────────────────────────────────────────────────

check_sql_auth() {
  if ! command -v sqlcmd &>/dev/null; then
    warn "sqlcmd no está en PATH — test de autenticación SQL omitido."
    warn "Instala mssql-tools (Linux) o SQL Server tools (Windows) para habilitarlo."
    return 0
  fi

  if [[ -z "${DB_USER:-}" ]] || [[ -z "${DB_PASS:-}" ]]; then
    warn "No hay User ID o Password en el connection string."
    warn "Autenticación integrada (Trusted Connection) no se puede verificar desde bash."
    return 0
  fi

  log "Probando autenticación SQL con sqlcmd (SELECT 1)..."

  local output exit_code=0
  output="$(sqlcmd \
    -S "${DB_HOST},${DB_PORT}" \
    -d "$DB_NAME" \
    -U "$DB_USER" \
    -P "$DB_PASS" \
    -Q "SELECT 1" \
    -b \
    -t 10 \
    2>&1)" || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    ok "SQL auth: login y SELECT 1 exitosos."
    return 0
  else
    err "SQL auth: sqlcmd falló (exit $exit_code)."
    err "     Salida: $output"
    err "     Verifica: User ID, Password, nombre de base de datos y permisos."
    return 1
  fi
}

# ── MAIN ───────────────────────────────────────────────────────────────────────

detect_os
conditional_require_root
load_connection_string "${1:-}"
parse_connection_string "$CONNECTION_STRING"
print_parsed_summary

FAILED_CHECKS=0

step "1 de 3 — Resolución DNS"
check_dns    || { (( FAILED_CHECKS += 1 )) || true; }

step "2 de 3 — Conectividad TCP"
check_tcp    || { (( FAILED_CHECKS += 1 )) || true; }

step "3 de 3 — Autenticación SQL"
check_sql_auth || { (( FAILED_CHECKS += 1 )) || true; }

step "Resultado"
if [[ $FAILED_CHECKS -eq 0 ]]; then
  ok "Todos los checks pasaron. El servidor puede comunicarse con la base de datos."
  exit 0
else
  err "$FAILED_CHECKS check(s) fallaron. Revisa los errores anteriores."
  exit 1
fi
