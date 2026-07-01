#!/usr/bin/env bash
# =============================================================================
# bin/menu.sh — Main operations menu (modular)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# If running from /app/scripts, adjust paths
if [[ -d "$SCRIPT_DIR/modules" ]]; then
  MODULES_DIR="$SCRIPT_DIR/modules"
elif [[ -d "$BASE_DIR/modules" ]]; then
  MODULES_DIR="$BASE_DIR/modules"
else
  MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/modules"
fi

source "$BASE_DIR/core/logger.sh" 2>/dev/null || source "$MODULES_DIR/../core/logger.sh" 2>/dev/null || {
  # Fallback: define inline if core not found
  log() { echo -e "\033[1;34m==> $*\033[0m"; }
  err() { echo -e "\033[1;31mERR  $*\033[0m" >&2; }
}
source "$BASE_DIR/core/input.sh" 2>/dev/null || source "$MODULES_DIR/../core/input.sh" 2>/dev/null || {
  menu_select() {
    local prompt="$1"; shift
    local options=("$@")
    local num=${#options[@]}
    echo; echo "$prompt"
    for i in "${!options[@]}"; do echo "  $((i+1))) ${options[$i]}"; done
    while true; do
      read -rp "Opcion: " idx
      if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= num )); then
        MENU_SELECTION="${options[$((idx-1))]}"
        return
      fi
    done
  }
}

# P1: divider() se define aca como FALLBACK defensivo por si core/logger.sh no
# se pudo sourcear (bloque de arriba). Si logger.sh cargo bien, esta redefinicion
# es identica y no cambia comportamiento. Se mantiene a proposito por resiliencia.
divider() { echo "========================================"; }

# M5: linea de estado rapido del sistema. Todo defensivo (2>/dev/null + fallback)
# para NO romper si el backend no esta instalado o systemctl no existe.
show_status_line() {
  local backend_state backend_ver
  backend_state="$(systemctl is-active backend 2>/dev/null || echo 'unknown')"
  backend_ver="$(readlink /app/backend/current 2>/dev/null | xargs -r basename 2>/dev/null || echo '?')"
  [[ -z "$backend_ver" ]] && backend_ver='?'
  echo "  Backend: ${backend_state} (v${backend_ver})"
}

while true; do
  echo
  divider
  echo "  EB Deploy Console"
  show_status_line
  divider
  menu_select "Seleccione una accion:" \
    "Backend (install/update/rollback)" \
    "Frontend (install/update/rollback)" \
    "App Health (check/status)" \
    "Database" \
    "Nginx" \
    "System" \
    "Release" \
    "Salir"

  # '|| true' en cada submenu: si un submenu sale non-zero (ej. exit 130 por
  # Ctrl+C, o un comando que falla), NO queremos que 'set -e' cierre la consola
  # principal. El operador debe volver al menu, no quedar afuera.
  case "$MENU_SELECTION" in
    "Backend (install/update/rollback)")  bash "$MODULES_DIR/backend/menu.sh" || true ;;
    "Frontend (install/update/rollback)") bash "$MODULES_DIR/frontend/menu.sh" || true ;;
    "App Health (check/status)")          bash "$MODULES_DIR/health/menu.sh" || true ;;
    "Database")                           bash "$MODULES_DIR/database/menu.sh" || true ;;
    "Nginx")                              bash "$MODULES_DIR/nginx/menu.sh" || true ;;
    "System")                             bash "$MODULES_DIR/system/menu.sh" || true ;;
    "Release")                            bash "$MODULES_DIR/release/menu.sh" || true ;;
    "Salir")                              log "Bye."; exit 0 ;;
  esac
  # C3: no pausamos aca. Cada submenu ya gestiona su propia pausa "Presiona
  # Enter" tras ejecutar un comando. Volver al menu principal solo redibuja.
done
