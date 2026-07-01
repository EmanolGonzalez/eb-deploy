#!/usr/bin/env bash
# =============================================================================
# core/filesystem.sh — Filesystem and symlink operations
# =============================================================================

INSTALL_BASE="${INSTALL_BASE:-/app}"

# Extract a RAR archive to a release directory
extract_rar() {
  local component="$1" version="$2" artifact_path="$3"
  local releases_dir="${INSTALL_BASE}/releases/${component}"
  local release_dir="${releases_dir}/${version}"
  local tmp_archive="/tmp/${component}-${version}-$$.rar"

  mkdir -p "$release_dir"

  # Clean slate: si esta version ya existia, limpiar antes de extraer.
  # Los assets de Vite (frontend) llevan hash en el nombre; al recompilar
  # cambian. Sin limpiar, los JS viejos quedarian de basura mezclados con
  # los nuevos (disco + confusion). unrar -y solo pisa los de igual nombre.
  if [[ -n "$(ls -A "$release_dir" 2>/dev/null)" ]]; then
    warn "La version $version ya existia en disco — limpiando para evitar mezcla de archivos."
    rm -rf "${release_dir:?}/"*
  fi

  log "Copiando artefacto a ubicacion temporal..."
  cp "$artifact_path" "$tmp_archive"

  log "Extrayendo en $release_dir..."
  if ! unrar x -y "$tmp_archive" "$release_dir/"; then
    err "Extraccion fallida."
    rm -f "$tmp_archive"
    return 1
  fi

  rm -f "$tmp_archive"
  RELEASE_DIR="$release_dir"
  ok "Artifact extraido en $RELEASE_DIR"
}

# Update the current symlink for a component
update_symlink() {
  local component="$1" release_dir="$2"
  local link_dir="${INSTALL_BASE}/${component}"
  local current_link="${link_dir}/current"
  mkdir -p "$link_dir"
  ln -sfn "$release_dir" "$current_link"
  ok "Symlink actualizado: $current_link -> $release_dir"
}

# Get current version from symlink
get_current_version() {
  local component="$1"
  local current_link="${INSTALL_BASE}/${component}/current"
  if [[ -L "$current_link" ]]; then
    basename "$(readlink "$current_link")"
  fi
}

# List local versions for a component
list_local_versions() {
  local component="$1"
  local releases_dir="${INSTALL_BASE}/releases/${component}"

  if [[ ! -d "$releases_dir" ]]; then
    return
  fi

  mapfile -t versions < <(ls -1 "$releases_dir" 2>/dev/null | sort -V)
  if [[ ${#versions[@]} -gt 0 ]]; then
    log "Versiones instaladas localmente: ${versions[*]}"
    LOCAL_VERSIONS=("${versions[@]}")
  fi
}

# Save previous version for rollback
save_previous_version() {
  local component="$1"
  local current_link="${INSTALL_BASE}/${component}/current"
  PREVIOUS_VERSION=""

  if [[ -L "$current_link" ]]; then
    PREVIOUS_VERSION="$(basename "$(readlink "$current_link")")"
    printf '%s' "$PREVIOUS_VERSION" > "${INSTALL_BASE}/${component}/previous_version.txt"
    log "Version anterior guardada para rollback: $PREVIOUS_VERSION"
  fi
}

# Validate that a file exists and is a .rar
validate_rar_file() {
  local path="$1"
  path="${path//\"/}"

  if [[ ! -f "$path" ]]; then
    err "Archivo no encontrado: $path"
    return 1
  fi

  if [[ "${path,,}" != *.rar ]]; then
    err "El archivo debe tener extension .rar"
    err "Ruta: '$path'"
    return 1
  fi

  ok "Archivo validado: $path ($(du -h "$path" | cut -f1))"
}
