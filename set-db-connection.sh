#!/usr/bin/env bash
set -e

DB_CONNECTION_FILE="/app/config/db-connection.txt"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
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
    return 1
  fi

  if ! grep -q '"DefaultConnection"' "$target_file"; then
    err "DefaultConnection key not found in: $target_file"
    return 1
  fi

  local escaped
  escaped="$(escape_for_sed_replacement "$connection_string")"

  sed -i -E "s#(\"DefaultConnection\"[[:space:]]*:[[:space:]]*\").*(\")#\\1${escaped}\\2#" "$target_file"
  log "Connection string updated in $target_file"
}

require_root

if [[ -n "${1:-}" ]]; then
  CONNECTION_STRING="$1"
else
  read -rsp "Enter ConnectionStrings:DefaultConnection value: " CONNECTION_STRING
  echo
fi

if [[ -z "$CONNECTION_STRING" ]]; then
  err "Connection string is required."
  exit 1
fi

mkdir -p /app/config
printf '%s' "$CONNECTION_STRING" > "$DB_CONNECTION_FILE"
chmod 600 "$DB_CONNECTION_FILE"
log "Connection string saved in $DB_CONNECTION_FILE"

CURRENT_APPSETTINGS="/app/backend/current/publish/appsettings.json"
if [[ -f "$CURRENT_APPSETTINGS" ]]; then
  apply_connection_string_to_file "$CURRENT_APPSETTINGS" "$CONNECTION_STRING"
  read -rp "Restart backend service now? [Y/n]: " restart_now
  if [[ -z "$restart_now" || "$restart_now" =~ ^[Yy]$ ]]; then
    systemctl restart backend
    log "Backend service restarted."
  fi
else
  log "Current backend appsettings not found. It will be applied automatically on next install/update."
fi

log "Done."
