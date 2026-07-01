#!/usr/bin/env bash
# =============================================================================
# core/deployment.sh — Shared deploy lifecycle (install / update / rollback)
#
# install_component  : deploy NEW release from /app/artifacts/<component>.rar
# update_component   : switch to ANY existing version in /app/releases/<component>/
# rollback_component : switch to the immediately previous version (one step back)
# =============================================================================

DEPLOYMENT_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEPLOYMENT_CORE_DIR/logger.sh"
source "$DEPLOYMENT_CORE_DIR/input.sh"
source "$DEPLOYMENT_CORE_DIR/config.sh"
source "$DEPLOYMENT_CORE_DIR/db.sh"
source "$DEPLOYMENT_CORE_DIR/filesystem.sh"
source "$DEPLOYMENT_CORE_DIR/service.sh"
source "$DEPLOYMENT_CORE_DIR/health.sh"
source "$DEPLOYMENT_CORE_DIR/checksum.sh"
source "$DEPLOYMENT_CORE_DIR/audit.sh"

INSTALL_BASE="${INSTALL_BASE:-/app}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/app/artifacts}"

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# install_component <component>
#   Deploy a NEW release from /app/artifacts/<component>.rar
# -----------------------------------------------------------------------------
install_component() {
  local component="$1"

  require_root
  load_config
  load_db_connection_if_exists
  ensure_db_connection_for_backend "$component"

  local artifact_path="${ARTIFACTS_DIR}/${component}.rar"
  echo
  if [[ ! -f "$artifact_path" ]]; then
    err "No se encontro $artifact_path"
    err "Copia el .rar a ${ARTIFACTS_DIR}/${component}.rar antes de continuar."
    exit 1
  fi
  validate_rar_file "$artifact_path" || exit 1

  local version
  read -rp "Version a instalar (ej: 1.2.3): " version
  if [[ -z "$version" ]] || ! [[ "$version" =~ ^[A-Za-z0-9._-]+$ ]]; then
    err "Version invalida."
    exit 1
  fi

  list_local_versions "$component"

  log "Generando checksum SHA256 del artifact..."
  checksum_artifact "$component" "$version" "$artifact_path"

  extract_rar "$component" "$version" "$artifact_path" || exit 1
  update_symlink "$component" "$RELEASE_DIR"

  if [[ "$component" == "backend" ]]; then
    restart_service "backend"
  fi

  audit_log "INSTALL" "$component" "$version" "OK" "Artifact: $artifact_path"
  rm -f "$artifact_path"
  log "Instalacion de $component v${version} completada exitosamente."
}

# -----------------------------------------------------------------------------
# update_component <component>
#   Switch to ANY existing version under /app/releases/<component>/
#   Runs healthcheck with auto-rollback on failure.
# -----------------------------------------------------------------------------
update_component() {
  local component="$1"

  require_root
  load_config
  load_db_connection_if_exists
  ensure_db_connection_for_backend "$component"

  local releases_dir="${INSTALL_BASE}/releases/${component}"
  if [[ ! -d "$releases_dir" ]]; then
    err "No hay releases instalados para $component en $releases_dir"
    err "Ejecuta 'deploy $component install' primero."
    exit 1
  fi

  mapfile -t available < <(ls -1 "$releases_dir" 2>/dev/null | sort -V)
  if [[ ${#available[@]} -eq 0 ]]; then
    err "No hay versiones disponibles para $component."
    exit 1
  fi

  local current
  current="$(get_current_version "$component")"
  if [[ -n "$current" ]]; then
    log "Version actual de $component: $current"
  fi

  menu_select "Selecciona la version a activar:" "${available[@]}"
  local target_version="$MENU_SELECTION"

  if [[ "$target_version" == "$current" ]]; then
    log "La version $target_version ya esta activa. Nada que hacer."
    return 0
  fi

  save_previous_version "$component"

  local target_dir="${releases_dir}/${target_version}"
  update_symlink "$component" "$target_dir"

  if [[ "$component" == "backend" ]]; then
    restart_service_soft "backend"
  fi

  local prev_release_dir="${releases_dir}/${PREVIOUS_VERSION:-}"
  if run_healthcheck_or_rollback "$component" "$PREVIOUS_VERSION" "$prev_release_dir"; then
    audit_log "UPDATE" "$component" "$target_version" "OK" "Switch local desde ${PREVIOUS_VERSION:-none}"
    log "Update de $component a v${target_version} completado exitosamente."
  else
    audit_log "UPDATE" "$component" "$target_version" "FAILED" "Healthcheck fallo, rollback ejecutado"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# rollback_component <component>
#   Switch to the immediately previous version (no menu, no choice).
# -----------------------------------------------------------------------------
rollback_component() {
  local component="$1"

  require_root
  load_config || true
  load_db_connection_if_exists
  ensure_db_connection_for_backend "$component"

  local previous_file="${INSTALL_BASE}/${component}/previous_version.txt"
  if [[ ! -f "$previous_file" ]]; then
    err "No hay version anterior registrada para $component."
    err "Usa 'deploy $component update' para elegir una version manualmente."
    exit 1
  fi

  local target_version
  target_version="$(cat "$previous_file")"
  if [[ -z "$target_version" ]]; then
    err "El registro de version anterior esta vacio."
    exit 1
  fi

  local target_dir="${INSTALL_BASE}/releases/${component}/${target_version}"
  if [[ ! -d "$target_dir" ]]; then
    err "La version anterior ya no esta disponible en disco: $target_dir"
    exit 1
  fi

  local current
  current="$(get_current_version "$component")"
  log "Rollback de $component: $current -> $target_version"

  local current_link="${INSTALL_BASE}/${component}/current"
  ln -sfn "$target_dir" "$current_link"
  ok "Symlink restaurado."

  if [[ "$component" == "backend" ]]; then
    restart_service_soft "backend"
  fi

  log "Ejecutando healthcheck (soft)..."
  run_healthcheck "$component" --soft || true

  audit_log "ROLLBACK" "$component" "$target_version" "OK" "Volvio a la version anterior"
  log "Rollback de $component a v${target_version} completado."
}
