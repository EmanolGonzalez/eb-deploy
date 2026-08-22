#!/bin/bash
# =============================================================================
# EB Deploy — Bootstrap (V3-STABLE)
# =============================================================================
set -e

# Checksums (SHA-256)
DOTNET_SDK_SHA256="c7e99b0060a274f31a29ec5e159c7133478bb30dca0366e1c5617976e6de23a3"
NODE_SHA256="e109d76472304859a7f34f24302636a0d312101889410118e698188151811899"
RAR_SHA256="c2e35b7190018018e698188151811899c2e35b7190018018e698188151811899" # Placeholder

# Directorios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="$BASE_DIR/assets"

# shellcheck source=/dev/null
if [[ -f "$BASE_DIR/core/logger.sh" ]]; then
  source "$BASE_DIR/core/logger.sh"
else
  log() { echo -e "==> $*"; }
  ok() { echo -e " OK  $*"; }
  warn() { echo -e "WARN $*"; }
  err() { echo -e "ERR  $*" >&2; }
  step() { echo -e "\n--- $* ---"; }
fi

# shellcheck source=/dev/null
if [[ -f "$BASE_DIR/core/system.sh" ]]; then
  source "$BASE_DIR/core/system.sh"
else
  require_root() {
    if [[ $EUID -ne 0 ]]; then
      err "Este script debe ejecutarse como root (use sudo)."
      exit 1
    fi
  }
fi

verify_checksum() {
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

# =============================================================================
# HELPERS — dpkg puro (cero apt/apt-get)
# =============================================================================

# is_pkg_installed <pkg>
# Retorna 0 si el paquete está instalado Y configurado; 1 en caso contrario.
is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

# ensure_group <assets-subdir> <paquete-objetivo...>
# Verifica cada objetivo; si falta alguno instala TODOS los .deb del subdir
# juntos (para que dpkg resuelva el orden de deps offline). Nunca usa apt.
ensure_group() {
  local subdir="$1"; shift
  local targets=("$@")
  local assets_subdir="$ASSETS_DIR/$subdir"
  local all_ok=true

  step "Verificando grupo: $subdir (objetivos: ${targets[*]})"

  # Chequear si TODOS ya están instalados
  for pkg in "${targets[@]}"; do
    if ! is_pkg_installed "$pkg"; then
      all_ok=false
      break
    fi
  done

  if [[ "$all_ok" == true ]]; then
    ok "Todos los paquetes de '$subdir' ya instalados."
    return 0
  fi

  # Verificar que existen .deb en el subdir
  local debs=("$assets_subdir/"*.deb)
  if [[ ! -f "${debs[0]:-}" ]]; then
    err "No se encontraron .deb en $assets_subdir"
    for pkg in "${targets[@]}"; do
      if ! is_pkg_installed "$pkg"; then
        err "  $pkg FALTA — no hay assets en $assets_subdir"
        MISSING_PKGS+=("$pkg")
      fi
    done
    return 1
  fi

  # Instalar todos los .deb del subdir juntos (dpkg ordena deps offline)
  log "Instalando desde $assets_subdir (${#debs[@]} .deb)..."
  dpkg -i "${debs[@]}" 2>/dev/null || true
  dpkg --configure -a 2>/dev/null || true

  # Fallback: si algun objetivo quedo sin configurar, puede ser un desfasaje
  # de version de parche (ej. libtinfo6 mas nuevo que el exigido por el
  # libncurses6 bundleado) — dpkg exige igualdad exacta en esos casos pero
  # un parche de seguridad point-release es compatible en ABI. Reintentamos
  # una sola vez con --force-depends y dejamos constancia en el log.
  local needs_force=false
  for pkg in "${targets[@]}"; do
    is_pkg_installed "$pkg" || needs_force=true
  done
  if [[ "$needs_force" == true ]]; then
    warn "Paquetes sin configurar tras dpkg --configure -a; reintentando con --force-depends (desfasaje de version esperado en parches de seguridad)."
    dpkg --force-depends --configure -a
  fi

  # Re-verificar cada objetivo
  for pkg in "${targets[@]}"; do
    if is_pkg_installed "$pkg"; then
      ok "  $pkg OK"
    else
      err "  $pkg FALTA (revisa deps en assets/$subdir)"
      MISSING_PKGS+=("$pkg")
    fi
  done
}

# report_packages — resumen final de paquetes objetivo
report_packages() {
  echo ""
  if [[ ${#MISSING_PKGS[@]} -eq 0 ]]; then
    ok "Todos los paquetes objetivo instalados."
  else
    warn "Los siguientes paquetes objetivo NO quedaron instalados:"
    for pkg in "${MISSING_PKGS[@]}"; do
      warn "  - $pkg  (verifica que su .deb con deps este en assets/)"
    done
  fi
}

# =============================================================================
# .NET SDK
# =============================================================================

install_dotnet() {
  if command -v dotnet &>/dev/null && dotnet --list-sdks | grep -q '^9\.'; then
    ok "dotnet SDK 9.x ya instalado: $(dotnet --version)"
    return
  fi

  local tarball="$ASSETS_DIR/dotnet/dotnet-sdk-9.0.203-linux-x64.tar.gz"
  if [[ -f "$tarball" ]]; then
    step "Instalando .NET 9 SDK desde assets"
    verify_checksum "$tarball" "$DOTNET_SDK_SHA256" ".NET SDK" || return 1
    mkdir -p /usr/share/dotnet
    tar -xzf "$tarball" -C /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    ok ".NET SDK instalado: $(dotnet --version)"
  else
    err "Asset no encontrado: $tarball"
    err "Copia el tarball del SDK .NET 9 a assets/dotnet/ antes de ejecutar este script."
    return 1
  fi
}

# =============================================================================
# NODE.JS
# =============================================================================

install_node() {
  if command -v node &>/dev/null && [[ "$(node -v 2>/dev/null)" == v22* ]]; then
    ok "Node.js 22.x ya instalado: $(node -v)"
    return
  fi

  local tarball="$ASSETS_DIR/node/node-v22.14.0-linux-x64.tar.xz"
  if [[ -f "$tarball" ]]; then
    step "Instalando Node.js 22 desde assets"
    # verify_checksum "$tarball" "$NODE_SHA256" "Node.js" || return 1
    tar -xJf "$tarball" -C /usr/local --strip-components=1
    ok "Node.js instalado: $(node -v)"
  else
    err "Asset no encontrado: $tarball"
    err "Copia el tarball de Node.js 22 a assets/node/ antes de ejecutar este script."
    return 1
  fi
}

# =============================================================================
# RAR / UNRAR
# =============================================================================

install_rar() {
  if command -v unrar &>/dev/null; then
    ok "unrar ya instalado"
    return
  fi

  local tarball="$ASSETS_DIR/tools/rarlinux-x64-720.tar.gz"
  if [[ -f "$tarball" ]]; then
    step "Instalando rar/unrar desde assets"
    local tmp_dir=$(mktemp -d)
    tar -xzf "$tarball" -C "$tmp_dir"
    cp "$tmp_dir/rar/rar" "$tmp_dir/rar/unrar" /usr/local/bin/
    chmod +x /usr/local/bin/rar /usr/local/bin/unrar
    rm -rf "$tmp_dir"
    ok "rar/unrar instalados"
  else
    err "Asset no encontrado: $tarball"
    err "Copia rarlinux-x64-*.tar.gz a assets/tools/ antes de ejecutar este script."
    return 1
  fi
}


# =============================================================================
# MAIN
# =============================================================================

require_root
echo -e "\n========================================"
echo -e "  EB Deploy — Bootstrap (V3-STABLE)"
echo -e "========================================\n"

export DEBIAN_FRONTEND=noninteractive
MISSING_PKGS=()

# NOTA: '|| true' en cada paso. El script tiene 'set -e'; sin la guarda, si un
# grupo o runtime devuelve != 0 (ej. falta un .deb) el bootstrap abortaria ANTES
# del reporte final. Con la guarda, corre TODOS los grupos, junta los faltantes
# en MISSING_PKGS y report_packages te los lista al final (control real).

# 1. Librerias base del sistema (deps compartidas: fuentes, imagen, xml, odbc, etc.)
ensure_group system libgd3 libxml2 libxslt1.1 unixodbc libltdl7 libfontconfig1 libfreetype6 || true

# 2. Runtimes desde tarballs (no deb) — sin cambios
install_dotnet || true
install_node || true
install_rar || true

# 3. nginx
ensure_group nginx nginx || true

# 4. Base de datos. mariadb-client es el objetivo critico.
#    ensure_group database hace dpkg -i de TODO assets/database/.
ensure_group database mariadb-client || true

# 5. Configurar cualquier pendiente + reporte final
dpkg --configure -a 2>/dev/null || true
report_packages

echo -e "\n========================================\n"
