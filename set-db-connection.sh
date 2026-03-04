#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# set-db-connection.sh — Configura o cambia la cadena de conexión de BD
# Guarda DB_CONNECTION_STRING en /app/config/config.env (chmod 600).
# La aplica en appsettings.json del backend actual si existe.
#
# Uso:
#   bash set-db-connection.sh
#   bash set-db-connection.sh "Server=...;Database=...;..."
# =============================================================================

CONFIG_FILE="/app/config/config.env"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }
ok()  { echo -e "\033[1;32m OK  $*\033[0m"; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

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
    return 1
  fi
  if ! grep -q '"DefaultConnection"' "$target_file"; then
    err "Clave DefaultConnection no encontrada en: $target_file"
    return 1
  fi
  local escaped
  escaped="$(escape_for_sed_replacement "$connection_string")"
  sed -i -E "s#(\"DefaultConnection\"[[:space:]]*:[[:space:]]*\").*(\")#\\1${escaped}\\2#" "$target_file"
  ok "Cadena de conexión aplicada a $target_file"
}

require_root

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "Archivo de configuración no encontrado: $CONFIG_FILE"
  err "Ejecuta setup-server.sh primero."
  exit 1
fi

# Leer valor actual desde config.env
# shellcheck source=/dev/null
source "$CONFIG_FILE"
CURRENT_CS="${DB_CONNECTION_STRING:-}"

if [[ -n "$CURRENT_CS" ]]; then
  log "Cadena de conexión configurada actualmente (oculta por seguridad)."
fi

# Aceptar como argumento o pedir interactivamente (input silencioso)
if [[ -n "${1:-}" ]]; then
  CONNECTION_STRING="$1"
else
  read -rsp "Nueva ConnectionStrings:DefaultConnection (input oculto): " CONNECTION_STRING
  echo
fi

if [[ -z "$CONNECTION_STRING" ]]; then
  err "La cadena de conexión no puede estar vacía."
  exit 1
fi

# Guardar en config.env
update_config_value "DB_CONNECTION_STRING" "$CONNECTION_STRING"
ok "DB_CONNECTION_STRING guardada en $CONFIG_FILE"

# Aplicar en el backend actual si existe
CURRENT_APPSETTINGS="/app/backend/current/appsettings.json"
if [[ -f "$CURRENT_APPSETTINGS" ]]; then
  apply_connection_string_to_file "$CURRENT_APPSETTINGS" "$CONNECTION_STRING"
  read -rp "¿Reiniciar el servicio backend ahora? [Y/n]: " restart_now
  if [[ -z "$restart_now" || "$restart_now" =~ ^[Yy]$ ]]; then
    systemctl restart backend
    ok "Servicio backend reiniciado."
  fi
else
  log "No hay backend desplegado actualmente. Se aplicará automáticamente en el próximo install/update."
fi

log "Listo."
