#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# rollback.sh — Restaura un componente a una versión previamente instalada
# Opera completamente en local (no requiere Azure ni SAS token).
# Puede ser llamado manualmente desde ops-menu.sh o automáticamente por update.sh.
# =============================================================================

CONFIG_FILE="/app/config/config.env"
INSTALL_BASE="/app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ----------------------------- UTILIDADES ------------------------------------

log()  { echo -e "\033[1;34m==> $*\033[0m"; }
err()  { echo -e "\033[1;31mError: $*\033[0m" >&2; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }

arrow_select() {
  local prompt="$1"; shift
  local options=("$@")
  local num=${#options[@]}
  local idx
  echo
  echo "$prompt"
  echo "Escribe el número de la opción y presiona Enter:"
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}"
  done
  while true; do
    read -rp "Opción: " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= num )); then
      ARROW_SELECTION="${options[$((idx-1))]}"
      return
    fi
    err "Opción inválida. Introduce un número entre 1 y $num."
  done
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

# ----------------------------- CONFIG ----------------------------------------

update_config_value() {
  local key="$1" value="$2"
  local safe="${value//\\/\\\\}"; safe="${safe//\"/\\\"}"
  local tmp found=false
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^"${key}=" ]]; then
      printf '%s="%s"\n' "$key" "$safe" >> "$tmp"
      found=true
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$CONFIG_FILE"
  [[ "$found" == false ]] && printf '\n%s="%s"\n' "$key" "$safe" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    # rollback opera en local — puede continuar sin config.env
    # pero advertimos porque podría indicar un servidor mal configurado
    log "Aviso: $CONFIG_FILE no encontrado. Continuando sin configuración central."
    return
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

# ----------------------------- BASE DE DATOS ---------------------------------

load_db_connection_if_exists() {
  if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
    log "Cadena de conexión cargada desde $CONFIG_FILE"
  fi
}

save_db_connection_string() {
  local value="$1"
  update_config_value "DB_CONNECTION_STRING" "$value"
  DB_CONNECTION_STRING="$value"
  ok "DB_CONNECTION_STRING guardada en $CONFIG_FILE"
}

prompt_new_db_connection_string() {
  local value
  read -rsp "ConnectionStrings:DefaultConnection: " value
  echo
  if [[ -z "$value" ]]; then
    err "La cadena de conexión no puede estar vacía."
    exit 1
  fi
  save_db_connection_string "$value"
}

ensure_db_connection_for_backend() {
  [[ "$COMPONENT" != "backend" ]] && return

  if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
    arrow_select "Cadena de conexión detectada. ¿Qué deseas hacer?" \
      "Usar cadena guardada" "Ingresar otra"
    [[ "$ARROW_SELECTION" == "Ingresar otra" ]] && prompt_new_db_connection_string
    return
  fi

  arrow_select "No hay cadena de conexión para backend." \
    "Ingresar ahora" "Continuar sin definir"
  [[ "$ARROW_SELECTION" == "Ingresar ahora" ]] && prompt_new_db_connection_string
}

escape_for_sed_replacement() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//&/\\&}"
  printf '%s' "$input"
}

apply_connection_string_to_file() {
  local target_file="$1"
  local connection_string="$2"

  if [[ ! -f "$target_file" ]]; then
    err "Archivo no encontrado: $target_file"
    exit 1
  fi
  if ! grep -q '"DefaultConnection"' "$target_file"; then
    err "Clave DefaultConnection no encontrada en: $target_file"
    exit 1
  fi
  local escaped
  escaped="$(escape_for_sed_replacement "$connection_string")"
  sed -i -E "s#(\"DefaultConnection\"[[:space:]]*:[[:space:]]*\").*(\")#\\1${escaped}\\2#" "$target_file"
  ok "Cadena de conexión aplicada a $target_file"
}

apply_db_connection_if_backend() {
  [[ "$COMPONENT" != "backend" ]] && return
  [[ -z "${DB_CONNECTION_STRING:-}" ]] && return

  local appsettings="${PREVIOUS_RELEASE_DIR}/appsettings.json"
  if [[ -f "$appsettings" ]]; then
    apply_connection_string_to_file "$appsettings" "$DB_CONNECTION_STRING"
  else
    log "appsettings.json no encontrado en versión de rollback. Se omite."
  fi
}

# ----------------------------- COMPONENTE ------------------------------------

select_component() {
  arrow_select "Selecciona el componente a restaurar:" frontend backend
  COMPONENT="$ARROW_SELECTION"
}

# ----------------------------- ARGUMENTOS ------------------------------------

parse_args() {
  COMPONENT=""
  PREVIOUS_VERSION=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --component)
        COMPONENT="$2"
        shift 2
        ;;
      --version)
        PREVIOUS_VERSION="$2"
        shift 2
        ;;
      *)
        err "Argumento desconocido: $1"
        err "Uso: bash rollback.sh [--component frontend|backend] [--version X.Y.Z]"
        exit 1
        ;;
    esac
  done
}

# ----------------------------- SELECCIÓN DE VERSIÓN --------------------------

select_version_from_local() {
  local releases_dir="${INSTALL_BASE}/releases/${COMPONENT}"

  if [[ ! -d "$releases_dir" ]]; then
    err "No se encontró el directorio de releases: $releases_dir"
    exit 1
  fi

  mapfile -t AVAILABLE_VERSIONS < <(ls -1 "$releases_dir" 2>/dev/null | sort -V)

  if [[ ${#AVAILABLE_VERSIONS[@]} -eq 0 ]]; then
    err "No hay versiones disponibles para rollback en $releases_dir"
    exit 1
  fi

  log "Versiones instaladas localmente: ${AVAILABLE_VERSIONS[*]}"
  arrow_select "Selecciona la versión a restaurar:" "${AVAILABLE_VERSIONS[@]}"
  PREVIOUS_VERSION="$ARROW_SELECTION"
}

# ----------------------------- MAIN ------------------------------------------

require_root
parse_args "$@"

load_config
load_db_connection_if_exists

if [[ -z "$COMPONENT" ]]; then
  select_component
fi

# Validar componente
case "$COMPONENT" in
  frontend|backend) ;;
  *)
    err "Componente inválido: '$COMPONENT'. Debe ser 'frontend' o 'backend'."
    exit 1
    ;;
esac

ensure_db_connection_for_backend

if [[ -z "$PREVIOUS_VERSION" ]]; then
  select_version_from_local
fi

RELEASES_DIR="${INSTALL_BASE}/releases/${COMPONENT}"
PREVIOUS_RELEASE_DIR="${RELEASES_DIR}/${PREVIOUS_VERSION}"

if [[ ! -d "$PREVIOUS_RELEASE_DIR" ]]; then
  err "Directorio de versión no encontrado: $PREVIOUS_RELEASE_DIR"
  exit 1
fi

apply_db_connection_if_backend

CURRENT_LINK="${INSTALL_BASE}/${COMPONENT}/current"
log "Restaurando symlink: $CURRENT_LINK -> $PREVIOUS_RELEASE_DIR"
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK"
ok "Symlink restaurado."

if [[ "$COMPONENT" == "backend" ]]; then
  log "Reiniciando servicio backend..."
  systemctl restart backend || true
  ok "Servicio backend reiniciado."
fi

log "Ejecutando healthcheck (soft)..."
bash "$SCRIPT_DIR/healthcheck.sh" "$COMPONENT" --soft || true

log "Rollback de $COMPONENT a v${PREVIOUS_VERSION} completado."
