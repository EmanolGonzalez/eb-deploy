#!/usr/bin/env bash
# =============================================================================
# core/checksum.sh — SHA256 checksum validation for artifacts
# =============================================================================

CHECKSUM_DIR="${CHECKSUM_DIR:-/app/deploy/.checksums}"

# Generate SHA256 checksum for a file
generate_checksum() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    err "Archivo no encontrado para checksum: $file"
    return 1
  fi
  sha256sum "$file" | awk '{print $1}'
}

# Save checksum for an artifact
save_checksum() {
  local component="$1" version="$2" checksum="$3"
  mkdir -p "$CHECKSUM_DIR"
  local checksum_file="$CHECKSUM_DIR/${component}-${version}.sha256"
  echo "$checksum" > "$checksum_file"
  ok "Checksum guardado para $component v$version"
}

# Verify checksum of an artifact against saved checksum
verify_checksum() {
  local component="$1" version="$2" file="$3"

  local checksum_file="$CHECKSUM_DIR/${component}-${version}.sha256"
  if [[ ! -f "$checksum_file" ]]; then
    warn "No hay checksum guardado para $component v$version. Se omitira la validacion."
    return 0
  fi

  local expected
  expected="$(cat "$checksum_file")"
  local actual
  actual="$(generate_checksum "$file")"

  if [[ "$expected" == "$actual" ]]; then
    ok "Checksum verificado para $component v$version"
    return 0
  else
    err "Checksum NO coincide para $component v$version"
    err "  Esperado: $expected"
    err "  Obtenido: $actual"
    err "  El artifact puede estar corrupto o no ser el original."
    return 1
  fi
}

# Generate and save checksum for an artifact (used during install/update)
checksum_artifact() {
  local component="$1" version="$2" file="$3"
  local checksum
  checksum="$(generate_checksum "$file")"
  save_checksum "$component" "$version" "$checksum"
  echo "$checksum"
}
