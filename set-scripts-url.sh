#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# set-scripts-url.sh — Configura o cambia la URL base raw de GitHub
# usada para actualizar los scripts desde ops-menu.sh.
#
# Guarda SCRIPTS_BASE_URL en /app/config/config.env.
# Uso:
#   bash set-scripts-url.sh
#   bash set-scripts-url.sh "https://raw.githubusercontent.com/usuario/repo/main"
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

require_root

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "Archivo de configuración no encontrado: $CONFIG_FILE"
  err "Ejecuta setup-server.sh primero."
  exit 1
fi

# Leer valor actual
CURRENT_URL=""
CURRENT_URL="$(grep -E '^SCRIPTS_BASE_URL=' "$CONFIG_FILE" | cut -d= -f2- | tr -d '"' || true)"

if [[ -n "$CURRENT_URL" ]]; then
  log "URL configurada actualmente: $CURRENT_URL"
else
  log "SCRIPTS_BASE_URL no está configurada todavía."
fi

# Aceptar como argumento o pedir interactivamente
if [[ -n "${1:-}" ]]; then
  NEW_URL="$1"
else
  echo
  read -rp "Nueva URL base raw de GitHub (Enter para mantener la actual): " NEW_URL
fi

# Sin cambio si el usuario presionó Enter con valor ya configurado
if [[ -z "$NEW_URL" && -n "$CURRENT_URL" ]]; then
  log "Sin cambios. URL sigue siendo: $CURRENT_URL"
  exit 0
fi

if [[ -z "$NEW_URL" ]]; then
  err "La URL es obligatoria si no hay una configurada."
  exit 1
fi

# Validación básica de formato
if [[ ! "$NEW_URL" =~ ^https?:// ]]; then
  err "La URL debe comenzar con https:// (o http://)"
  err "Ejemplo: https://raw.githubusercontent.com/usuario/repo/main"
  exit 1
fi

# Quitar trailing slash
NEW_URL="${NEW_URL%/}"

# Guardar en config.env
if grep -q '^SCRIPTS_BASE_URL=' "$CONFIG_FILE"; then
  sed -i "s|^SCRIPTS_BASE_URL=.*|SCRIPTS_BASE_URL=\"${NEW_URL}\"|" "$CONFIG_FILE"
else
  # La clave no existe todavía, agregarla
  printf '\nSCRIPTS_BASE_URL="%s"\n' "$NEW_URL" >> "$CONFIG_FILE"
fi

ok "SCRIPTS_BASE_URL guardada en $CONFIG_FILE"
log "URL activa: $NEW_URL"
log "Se usará en la próxima 'Actualizar scripts' desde ops-menu.sh"
