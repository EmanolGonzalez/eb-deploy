#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

arrow_select() {
  local prompt="$1"; shift
  local options=("$@")
  local num=${#options[@]}
  local idx
  echo
  echo "$prompt"
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

run_script() {
  local script_name="$1"
  shift
  if [[ ! -f "$SCRIPT_DIR/$script_name" ]]; then
    err "Script not found: $SCRIPT_DIR/$script_name"
    return 1
  fi
  bash "$SCRIPT_DIR/$script_name" "$@"
}

refresh_scripts() {
  local fetch_script="$SCRIPT_DIR/fetch-all.sh"
  local base_url=""

  read -rp "URL base raw de GitHub: " base_url
  if [[ -z "$base_url" ]]; then
    err "La URL base es obligatoria."
    return 1
  fi

  log "Actualizando fetch-all.sh..."
  wget -q -O "$fetch_script" "$base_url/fetch-all.sh" || {
    err "No se pudo descargar fetch-all.sh desde $base_url"
    return 1
  }
  chmod +x "$fetch_script"

  bash "$fetch_script" "$base_url"
  log "Scripts actualizados."
}

show_header() {
  echo
  echo "========================================"
  echo "  EB Deploy Console"
  echo "========================================"
}

require_root

while true; do
  show_header
  arrow_select "Seleccione una acción:" \
    "Status" \
    "Actualizar scripts" \
    "Install" \
    "Update" \
    "Rollback" \
    "Uninstall" \
    "Set DB connection" \
    "Set backend health endpoint" \
    "Configurar HTTPS interno" \
    "Healthcheck backend (soft)" \
    "Healthcheck frontend" \
    "Restart backend" \
    "Restart nginx" \
    "Logs backend (tail)" \
    "Logs nginx (tail)" \
    "Salir"

  case "$ARROW_SELECTION" in
    "Status")
      run_script "status.sh"
      ;;
    "Actualizar scripts")
      refresh_scripts
      ;;
    "Install")
      run_script "install.sh"
      ;;
    "Update")
      run_script "update.sh"
      ;;
    "Rollback")
      run_script "rollback.sh"
      ;;
    "Uninstall")
      run_script "uninstall.sh"
      ;;
    "Set DB connection")
      run_script "set-db-connection.sh"
      ;;
    "Set backend health endpoint")
      run_script "set-health-endpoint.sh"
      ;;
    "Configurar HTTPS interno")
      run_script "configure-internal-https.sh"
      ;;
    "Healthcheck backend (soft)")
      run_script "healthcheck.sh" backend --soft
      ;;
    "Healthcheck frontend")
      run_script "healthcheck.sh" frontend
      ;;
    "Restart backend")
      systemctl restart backend
      log "Backend restarted."
      ;;
    "Restart nginx")
      systemctl restart nginx
      log "Nginx restarted."
      ;;
    "Logs backend (tail)")
      journalctl -u backend -f
      ;;
    "Logs nginx (tail)")
      journalctl -u nginx -f
      ;;
    "Salir")
      log "Bye."
      exit 0
      ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
