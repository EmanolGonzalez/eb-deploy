#!/usr/bin/env bash
# =============================================================================
# modules/system/lib/runtime-install.sh
#
# Instalacion/actualizacion del SDK .NET desde assets/, compartida por
# setup/bootstrap.sh (primera instalacion) y
# modules/system/commands/update-runtimes.sh (servidor ya desplegado).
# Requiere que el que hace source ya haya definido ASSETS_DIR y las funciones
# de logging (log/ok/warn/err/step), p.ej. via core/logger.sh o core/system.sh.
# =============================================================================

# Version esperada del SDK .NET. Actualizar junto con DOTNET_SDK_SHA256 y el
# asset en assets/dotnet/ cuando se publique un parche de seguridad.
EXPECTED_DOTNET_SDK_VERSION="10.0.402"
DOTNET_SDK_SHA256="a131496fe7dac21dceea13354e50a3636126fac05d6e5ccf5fb250829c6e9b6a"

runtime_verify_checksum() {
  local file="$1"
  local expected="$2"
  local name="$3"

  if [[ -z "$expected" || "$expected" == "placeholder" ]]; then
    warn "Saltando verificacion de checksum para $name (sin hash definido)"
    return 0
  fi

  log "Verificando integridad de $name..."
  local actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    err "Checksum invalido para $name!"
    err "Esperado: $expected"
    err "Obtenido: $actual"
    return 1
  fi
  ok "Integridad verificada."
}

install_dotnet() {
  # Idempotente por version EXACTA del SDK esperado (EXPECTED_DOTNET_SDK_VERSION).
  # Un servidor con solo 9.x instalado NO debe saltar: el backend es net10.0.
  # Un servidor con un 10.x DISTINTO al esperado (p.ej. una version con CVE
  # conocido de un ensayo previo) tampoco debe saltar: se purga antes de
  # instalar la version correcta, para no dejar un SDK/runtime vulnerable activo.
  local installed_10x
  installed_10x="$(command -v dotnet &>/dev/null && dotnet --list-sdks 2>/dev/null | awk '{print $1}' | grep '^10\.' || true)"

  if printf '%s\n' "$installed_10x" | grep -qx "$EXPECTED_DOTNET_SDK_VERSION"; then
    ok "dotnet SDK $EXPECTED_DOTNET_SDK_VERSION ya instalado (version correcta): $(dotnet --version)"
    return
  fi

  local tarball="$ASSETS_DIR/dotnet/dotnet-sdk-${EXPECTED_DOTNET_SDK_VERSION}-linux-x64.tar.gz"
  if [[ -f "$tarball" ]]; then
    step "Instalando .NET 10 SDK ($EXPECTED_DOTNET_SDK_VERSION) desde assets"
    if dotnet --list-sdks 2>/dev/null | grep -q '^9\.'; then
      warn "SDK 9.x detectado; se conserva (coexiste en /usr/share/dotnet, no se toca)"
    fi

    if [[ -n "$installed_10x" ]]; then
      warn "SDK 10.x desactualizado detectado ($installed_10x); purgando antes de instalar $EXPECTED_DOTNET_SDK_VERSION"
      local old_ver
      for old_ver in $installed_10x; do
        rm -rf "/usr/share/dotnet/sdk/$old_ver" "/usr/share/dotnet/sdk-manifests/$old_ver"
      done
      # Runtimes 10.x huerfanos (el patch de runtime no siempre coincide con el
      # del SDK): se limpian por separado para no dejar ningun binario 10.x viejo.
      while read -r pkg ver; do
        [[ -z "$pkg" ]] && continue
        rm -rf "/usr/share/dotnet/shared/$pkg/$ver"
      done < <(dotnet --list-runtimes 2>/dev/null | awk '/^Microsoft\.(NETCore|AspNetCore)\.App 10\./{print $1, $2}')
      ok "SDK/runtime 10.x anteriores purgados."
    fi

    runtime_verify_checksum "$tarball" "$DOTNET_SDK_SHA256" ".NET SDK" || return 1
    mkdir -p /usr/share/dotnet
    tar -xzf "$tarball" -C /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    ok ".NET SDK instalado: $(dotnet --version)"
  else
    err "Asset no encontrado: $tarball"
    err "Copia el tarball del SDK .NET 10 a assets/dotnet/ antes de ejecutar este script."
    return 1
  fi
}
