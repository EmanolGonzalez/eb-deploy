#!/usr/bin/env bash
# =============================================================================
# bin/menu.sh — Main operations menu (task-based categories)
#
# The first level answers "¿qué quiero hacer?", not "¿qué componente es?". The
# categories are a VIEW: each entry dispatches to the SAME module command the
# CLI exposes (`deploy <module> <action>`), so automation, tests and runbooks
# keep working unchanged.
#
# Category 6 (Avanzado) is dev-gated: it only appears with DEPLOY_DEV_MODE=1.
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
source "$BASE_DIR/core/devmode.sh" 2>/dev/null || source "$MODULES_DIR/../core/devmode.sh" 2>/dev/null || {
  deploy_dev_mode() { [[ "${DEPLOY_DEV_MODE:-}" == "1" ]]; }
  dev_mode_banner() { deploy_dev_mode && echo "*** MODO DESARROLLADOR ACTIVO ***" || true; }
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

# ── Dispatch: una sola fuente de verdad para opcion -> comando ────────────────
# run_cmd <module> [action] [args...]
#   - sin action  -> abre el menu del modulo (selector de acciones)
#   - con action  -> ejecuta el comando del modulo directamente
# MENU_DRY_RUN=1 imprime el destino en vez de ejecutarlo (hook de test).
run_cmd() {
  local module="$1" action="${2:-}"
  if [[ $# -ge 2 ]]; then shift 2; else shift $#; fi
  if [[ "${MENU_DRY_RUN:-0}" == "1" ]]; then
    if [[ -z "$action" ]]; then
      echo "MENU-DISPATCH $module (menu)"
    else
      echo "MENU-DISPATCH $module $action $*"
    fi
    return 0
  fi
  if [[ -z "$action" ]]; then
    bash "$MODULES_DIR/$module/menu.sh" || true
  else
    bash "$MODULES_DIR/$module/commands/$action.sh" "$@" || true
  fi
}

pause_menu() { echo; read -rp "Presiona Enter para continuar..." _ 2>/dev/null || true; }

# ── Categorias ────────────────────────────────────────────────────────────────

# 1) ¿Como esta el sistema?
menu_category_estado() {
  while true; do
    echo; divider; echo "  ¿Cómo está el sistema?"; dev_mode_banner; divider
    menu_select "Selecciona una accion:" \
      "Estado del sistema (un toque)" \
      "Diagnóstico completo" \
      "Ver el historial de deploys (auditoría)" \
      "Volver al menu principal"
    case "$MENU_SELECTION" in
      "Estado del sistema (un toque)")            run_cmd health simple ;;
      "Diagnóstico completo")                      run_cmd health full ;;
      "Ver el historial de deploys (auditoría)")   run_cmd system audit ;;
      *) return 0 ;;
    esac
    pause_menu
  done
}

# 2) Respaldos (accion directa)
menu_respaldos() { run_cmd database backup; pause_menu; }

# 3) Actualizar la aplicacion (cada componente abre su menu de acciones)
menu_category_actualizar() {
  while true; do
    echo; divider; echo "  Actualizar la aplicación"; dev_mode_banner; divider
    menu_select "Selecciona una accion:" \
      "Backend: instalar / actualizar / volver" \
      "Frontend: instalar / actualizar / volver" \
      "Observabilidad: instalar / estado / actualizar" \
      "Volver al menu principal"
    case "$MENU_SELECTION" in
      "Backend: instalar / actualizar / volver")        run_cmd backend ;;
      "Frontend: instalar / actualizar / volver")       run_cmd frontend ;;
      "Observabilidad: instalar / estado / actualizar") run_cmd observability ;;
      *) return 0 ;;
    esac
    pause_menu
  done
}

# 4) Base de datos
menu_category_database() {
  while true; do
    echo; divider; echo "  Base de datos"; dev_mode_banner; divider
    menu_select "Selecciona una accion:" \
      "Crear base (si falta)" \
      "Verificar conexión" \
      "Reset de esquema (borra tablas, conserva la base)" \
      "Asignar rol Developer" \
      "Volver al menu principal"
    case "$MENU_SELECTION" in
      "Crear base (si falta)")                            run_cmd database create ;;
      "Verificar conexión")                              run_cmd database check ;;
      "Reset de esquema (borra tablas, conserva la base)") run_cmd database reset-schema ;;
      "Asignar rol Developer")                            run_cmd database set-developer ;;
      *) return 0 ;;
    esac
    pause_menu
  done
}

# 5) Configuracion y seguridad
menu_category_config() {
  while true; do
    echo; divider; echo "  Configuración y seguridad"; dev_mode_banner; divider
    menu_select "Selecciona una accion:" \
      "Editar config.env" \
      "HTTPS con certificado interno" \
      "Recargar nginx" \
      "Rotar llave RSA privada" \
      "Rotar Hash Key de PII" \
      "Gestionar servicios (start/stop/restart)" \
      "Volver al menu principal"
    case "$MENU_SELECTION" in
      "Editar config.env")                        run_cmd system edit-config ;;
      "HTTPS con certificado interno")            run_cmd nginx configure-https ;;
      "Recargar nginx")                           run_cmd nginx reload ;;
      "Rotar llave RSA privada")                  run_cmd system rotate-pem ;;
      "Rotar Hash Key de PII")                    run_cmd system rotate-pii ;;
      "Gestionar servicios (start/stop/restart)") run_cmd system services ;;
      *) return 0 ;;
    esac
    pause_menu
  done
}

# 6) Avanzado (dev-gated)
menu_category_avanzado() {
  while true; do
    echo; divider; echo "  🔧 Avanzado"; dev_mode_banner; divider
    menu_select "Selecciona una accion:" \
      "Let's Encrypt (dev)" \
      "Compilar y empaquetar (release)" \
      "Desinstalar" \
      "Volver al menu principal"
    case "$MENU_SELECTION" in
      "Let's Encrypt (dev)")               run_cmd nginx configure-letsencrypt ;;
      "Compilar y empaquetar (release)")   run_cmd release build ;;
      "Desinstalar")                       run_cmd system uninstall ;;
      *) return 0 ;;
    esac
    pause_menu
  done
}

# ── Menu principal ────────────────────────────────────────────────────────────
while true; do
  echo
  divider
  echo "  EB Deploy Console"
  echo "  ¿Qué querés hacer?"
  show_status_line
  dev_mode_banner
  divider
  local_options=(
    "¿Cómo está el sistema?"
    "Respaldos"
    "Actualizar la aplicación"
    "Base de datos"
    "Configuración y seguridad"
  )
  if deploy_dev_mode; then
    local_options+=("🔧 Avanzado")
  fi
  local_options+=("Salir")
  menu_select "Selecciona una categoría:" "${local_options[@]}"

  case "$MENU_SELECTION" in
    "¿Cómo está el sistema?")       menu_category_estado ;;
    "Respaldos")                    menu_respaldos ;;
    "Actualizar la aplicación")     menu_category_actualizar ;;
    "Base de datos")                menu_category_database ;;
    "Configuración y seguridad")    menu_category_config ;;
    "🔧 Avanzado")                   menu_category_avanzado ;;
    "Salir")                        log "Bye."; exit 0 ;;
    *)                              : ;;
  esac
done
