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
  local base_url="" configured_url=""

  # Leer SCRIPTS_BASE_URL desde config.env si existe
  local config_file="/app/config/config.env"
  if [[ -f "$config_file" ]]; then
    configured_url="$(grep -E '^SCRIPTS_BASE_URL=' "$config_file" | cut -d= -f2- | tr -d '"' || true)"
  fi

  if [[ -n "$configured_url" ]]; then
    # Mismo patrón que DB connection: mostrar la configurada y preguntar
    log "URL configurada: $configured_url"
    arrow_select "¿Qué URL deseas usar para actualizar los scripts?" \
      "Usar URL configurada" \
      "Ingresar otra"
    if [[ "$ARROW_SELECTION" == "Usar URL configurada" ]]; then
      base_url="$configured_url"
    else
      read -rp "Nueva URL base raw de GitHub: " base_url
      if [[ -z "$base_url" ]]; then
        err "La URL es obligatoria."
        return 1
      fi
    fi
  else
    # Primera vez: no hay URL configurada, pedir obligatoriamente
    log "SCRIPTS_BASE_URL no configurada. Puedes guardarla con 'Set scripts URL' en el menú."
    read -rp "URL base raw de GitHub (ej: https://raw.githubusercontent.com/usuario/repo/main): " base_url
    if [[ -z "$base_url" ]]; then
      err "La URL es obligatoria."
      return 1
    fi
  fi

  # fetch-all.sh se descarga en un archivo temporal — nunca queda en /app/scripts/
  local tmp_fetch
  tmp_fetch="$(mktemp /tmp/fetch-all-XXXXXX.sh)"
  trap 'rm -f "$tmp_fetch"' RETURN INT TERM

  log "Descargando fetch-all.sh (temporalmente en $tmp_fetch)..."
  if ! wget -q -O "$tmp_fetch" "$base_url/fetch-all.sh"; then
    err "No se pudo descargar fetch-all.sh desde: $base_url"
    err "Verifica la URL y la conectividad. Los scripts actuales no fueron modificados."
    return 1
  fi

  # Validación mínima: debe ser un script bash
  if ! grep -q '^#!/' "$tmp_fetch" 2>/dev/null; then
    err "El archivo descargado no parece un script válido (sin shebang)."
    err "Puede ser una respuesta de error de GitHub (URL incorrecta)."
    return 1
  fi

  chmod +x "$tmp_fetch"
  log "Ejecutando fetch-all.sh para actualizar scripts en $SCRIPT_DIR..."

  if ! bash "$tmp_fetch" "$base_url"; then
    err "fetch-all.sh finalizó con error. Revisa los mensajes anteriores."
    return 1
  fi

  # El trap elimina $tmp_fetch al retornar — fetch-all.sh no queda en disco
  log "Scripts actualizados correctamente. fetch-all.sh temporal eliminado."
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
    "Check DB connection" \
    "Set backend health endpoint" \
    "Set scripts URL" \
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
    "Check DB connection")
      run_script "check-db.sh"
      ;;
    "Set backend health endpoint")
      run_script "set-health-endpoint.sh"
      ;;
    "Set scripts URL")
      run_script "set-scripts-url.sh"
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
