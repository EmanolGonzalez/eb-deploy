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

divider() { echo "========================================"; }

while true; do
  echo
  divider
  echo "  EB Deploy Console"
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

  case "$MENU_SELECTION" in
    "Backend (install/update/rollback)")  bash "$MODULES_DIR/backend/menu.sh" ;;
    "Frontend (install/update/rollback)") bash "$MODULES_DIR/frontend/menu.sh" ;;
    "App Health (check/status)")          bash "$MODULES_DIR/health/menu.sh" ;;
    "Database")                           bash "$MODULES_DIR/database/menu.sh" ;;
    "Nginx")                              bash "$MODULES_DIR/nginx/menu.sh" ;;
    "System")                             bash "$MODULES_DIR/system/menu.sh" ;;
    "Release")                            bash "$MODULES_DIR/release/menu.sh" ;;
    "Salir")                              log "Bye."; exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
