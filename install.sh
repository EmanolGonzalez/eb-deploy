#!/usr/bin/env bash
set -e

# =============================================================================
# install.sh — Modular deployment script for Azure Blob Storage artifacts
# Supports frontend/backend, dynamic version listing, secure SAS token handling
# =============================================================================

# ----------------------------- UTILITY FUNCTIONS -----------------------------
log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

arrow_select() {
  local prompt="$1"; shift
  local options=("$@")
  local num=${#options[@]}
  local idx
  echo "$prompt"
  echo "Escribe el número de la opción deseada y presiona Enter:"
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

CONFIG_FILE="/app/config/storage.conf"
DB_CONNECTION_FILE="/app/config/db-connection.txt"
if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Configuration file $CONFIG_FILE not found."
  read -rp "Enter Azure Storage Account: " STORAGE_ACCOUNT
  read -rp "Enter Azure Container Name: " CONTAINER_NAME
  BASE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}"
  mkdir -p /app/config
  cat > "$CONFIG_FILE" <<EOF
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
CONTAINER_NAME="$CONTAINER_NAME"
BASE_URL="$BASE_URL"
EOF
  log "Configuration file created at $CONFIG_FILE."
else
  source "$CONFIG_FILE"
fi
INSTALL_BASE="/app"

load_db_connection_if_exists() {
  if [[ -f "$DB_CONNECTION_FILE" ]]; then
    DB_CONNECTION_STRING="$(cat "$DB_CONNECTION_FILE")"
    if [[ -n "$DB_CONNECTION_STRING" ]]; then
      log "DB connection string loaded from $DB_CONNECTION_FILE"
    fi
  fi
}

extract_connection_value() {
  local connection_string="$1"
  local key_regex="$2"
  echo "$connection_string" | sed -nE "s/.*${key_regex}=([^;]+).*/\1/ip"
}

connection_summary() {
  local connection_string="$1"
  local server database user

  server="$(extract_connection_value "$connection_string" 'server')"
  database="$(extract_connection_value "$connection_string" 'initial catalog|database')"
  user="$(extract_connection_value "$connection_string" 'user id|uid')"

  [[ -z "$server" ]] && server="(desconocido)"
  [[ -z "$database" ]] && database="(desconocida)"
  [[ -z "$user" ]] && user="(integrated/no user)"

  printf 'server=%s | db=%s | user=%s' "$server" "$database" "$user"
}

save_db_connection_string() {
  local connection_string="$1"
  mkdir -p /app/config
  printf '%s' "$connection_string" > "$DB_CONNECTION_FILE"
  chmod 600 "$DB_CONNECTION_FILE"
  DB_CONNECTION_STRING="$connection_string"
  log "DB connection string saved in $DB_CONNECTION_FILE"
}

prompt_new_db_connection_string() {
  local value
  read -rsp "Enter ConnectionStrings:DefaultConnection value: " value
  echo

  if [[ -z "$value" ]]; then
    err "Connection string is required."
    exit 1
  fi

  save_db_connection_string "$value"
}

ensure_db_connection_for_backend() {
  if [[ "$COMPONENT" != "backend" ]]; then
    return
  fi

  if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
    arrow_select "Se detectó una cadena de conexión guardada. ¿Qué deseas hacer?" "Usar cadena guardada" "Usar otra"

    if [[ "$ARROW_SELECTION" == "Usar otra" ]]; then
      prompt_new_db_connection_string
    else
      log "Using existing DB connection string."
    fi
    return
  fi

  arrow_select "No hay cadena de conexión guardada para backend." "Ingresar ahora" "Continuar sin definir"
  if [[ "$ARROW_SELECTION" == "Ingresar ahora" ]]; then
    prompt_new_db_connection_string
  else
    log "Continuing without DB connection string. appsettings.json will not be modified."
  fi
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
    err "File not found: $target_file"
    exit 1
  fi

  if ! grep -q '"DefaultConnection"' "$target_file"; then
    err "DefaultConnection key not found in: $target_file"
    exit 1
  fi

  local escaped
  escaped="$(escape_for_sed_replacement "$connection_string")"
  sed -i -E "s#(\"DefaultConnection\"[[:space:]]*:[[:space:]]*\").*(\")#\\1${escaped}\\2#" "$target_file"
  log "Connection string applied to $target_file"
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

prompt_sas_token() {
  if [[ -n "$AZURE_SAS_TOKEN" ]]; then
    SAS_TOKEN="$AZURE_SAS_TOKEN"
  else
    read -rsp "Enter Azure SAS token (e.g. sv=2024-...&sig=...): " SAS_TOKEN
    echo
    if [[ -z "$SAS_TOKEN" ]]; then
      err "SAS token is required."
      exit 1
    fi
    # Normalize: strip leading '?' if present
    SAS_TOKEN="${SAS_TOKEN#\?}"
    log "SAS token received: ${#SAS_TOKEN} characters (...${SAS_TOKEN: -6})"
  fi
}

select_component() {
  arrow_select "Select component to deploy:" frontend backend
  COMPONENT="$ARROW_SELECTION"
}

version_is_newer() {
  local candidate="$1"
  local current="$2"
  [[ "$candidate" != "$current" ]] && [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n1)" == "$candidate" ]]
}

list_versions() {
  # List available versions in Azure Blob Storage for the selected component
  local url="${BASE_URL}?restype=container&comp=list&prefix=${COMPONENT}/&${SAS_TOKEN}"
  log "Fetching available versions for $COMPONENT..."
  local xml
  if ! xml=$(curl -fsSL "$url"); then
    err "Failed to list blobs (HTTP error)."
    err "Verify: 1) SAS token is valid and not expired"
    err "        2) Token has 'Read' + 'List' permissions on the container"
    err "        3) Storage account '${STORAGE_ACCOUNT}' and container '${CONTAINER_NAME}' exist"
    exit 1
  fi
  mapfile -t VERSIONS < <(echo "$xml" | grep -oP '<Name>'"${COMPONENT}/\K[^/]+(?=/app\.rar)" | sort -Vu)
  if [[ ${#VERSIONS[@]} -eq 0 ]]; then
    err "No versions found for $COMPONENT."
    err "XML response (first 500 chars): ${xml:0:500}"
    exit 1
  fi
  log "Versions found: ${VERSIONS[*]}"
  # Detect current version
  local current_link="${INSTALL_BASE}/${COMPONENT}/current"
  if [[ -L "$current_link" ]]; then
    CURRENT_VERSION=$(basename "$(readlink "$current_link")")
    log "Current installed version: $CURRENT_VERSION"
    # Filter only versions greater than current
    FILTERED_VERSIONS=()
    for v in "${VERSIONS[@]}"; do
      if version_is_newer "$v" "$CURRENT_VERSION"; then
        FILTERED_VERSIONS+=("$v")
      fi
    done
    VERSIONS=("${FILTERED_VERSIONS[@]}")
    if [[ ${#VERSIONS[@]} -eq 0 ]]; then
      err "No newer versions available."
      exit 1
    fi
    log "Newer versions available: ${VERSIONS[*]}"
  fi
}

select_version() {
  arrow_select "Select version to install:" "${VERSIONS[@]}"
  VERSION="$ARROW_SELECTION"
}

download_and_extract() {
  local archive_url="${BASE_URL}/${COMPONENT}/${VERSION}/app.rar?${SAS_TOKEN}"
  local releases_dir="${INSTALL_BASE}/releases/${COMPONENT}"
  local release_dir="${releases_dir}/${VERSION}"
  local tmp_archive="/tmp/${COMPONENT}-${VERSION}.rar"
  mkdir -p "$release_dir"
  log "Downloading artifact: $archive_url"
  if ! curl -fSL "$archive_url" -o "$tmp_archive"; then
    err "Failed to download artifact."
    exit 1
  fi
  log "Extracting to $release_dir"
  if ! unrar x -y "$tmp_archive" "$release_dir/"; then
    err "Extraction failed."
    rm -f "$tmp_archive"
    exit 1
  fi
  rm -f "$tmp_archive"
  RELEASE_DIR="$release_dir"
}

update_symlink() {
  local link_dir="${INSTALL_BASE}/${COMPONENT}"
  local current_link="${link_dir}/current"
  mkdir -p "$link_dir"
  log "Updating symlink: $current_link -> $RELEASE_DIR"
  ln -sfn "$RELEASE_DIR" "$current_link"
}

restart_service_if_backend() {
  if [[ "$COMPONENT" == "backend" ]]; then
    log "Restarting systemd service: backend"
    systemctl restart backend || { err "Failed to restart backend service."; exit 1; }
  fi
}

apply_db_connection_if_backend() {
  if [[ "$COMPONENT" != "backend" ]]; then
    return
  fi

  if [[ -z "${DB_CONNECTION_STRING:-}" ]]; then
    log "DB connection string file not found ($DB_CONNECTION_FILE). Skipping appsettings.json update."
    return
  fi

  local backend_appsettings="${RELEASE_DIR}/publish/appsettings.json"
  apply_connection_string_to_file "$backend_appsettings" "$DB_CONNECTION_STRING"
}

# ----------------------------- MAIN LOGIC ------------------------------------
require_root
prompt_sas_token
load_db_connection_if_exists
select_component
ensure_db_connection_for_backend
list_versions
select_version
download_and_extract
apply_db_connection_if_backend
update_symlink
restart_service_if_backend

log "Installation of $COMPONENT version $VERSION completed successfully."
