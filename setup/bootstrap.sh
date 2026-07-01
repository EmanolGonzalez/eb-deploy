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
# SYSTEM PACKAGES
# =============================================================================

install_system_packages() {
  step "Instalando paquetes del sistema"
  local packages="curl git wget tar libltdl7 unixodbc libgd3 libxml2 libxslt1.1"
  local to_install=()
  for pkg in $packages; do
    if ! dpkg -l "$pkg" &>/dev/null; then to_install+=("$pkg"); fi
  done

  if [[ ${#to_install[@]} -gt 0 ]]; then
    # 1. Intentar instalar desde assets locales primero
    local sys_debs=("$ASSETS_DIR/system/"*.deb)
    if [[ -f "${sys_debs[0]:-}" ]]; then
      log "Instalando dependencias de sistema desde assets..."
      dpkg -i "${sys_debs[@]}" 2>/dev/null || true
      dpkg --configure -a 2>/dev/null || true
    fi

    # 2. Si todavia falta algo, intentar via apt
    to_install=()
    for pkg in $packages; do
      if ! dpkg -l "$pkg" &>/dev/null; then to_install+=("$pkg"); fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
      log "Instalando faltantes via apt: ${to_install[*]}"
      apt-get update -qq && apt-get install -y -qq "${to_install[@]}" || true
      
      # Cachear para la proxima
      mkdir -p "$ASSETS_DIR/system"
      cp /var/cache/apt/archives/*.deb "$ASSETS_DIR/system/" 2>/dev/null || true
    fi
  else
    ok "Paquetes del sistema ya instalados."
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
    warn "Asset no encontrado: $tarball. Intentando online..."
    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
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
    warn "Asset no encontrado: $tarball. Intentando online..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y -qq nodejs
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
    apt-get install -y -qq unrar || true
  fi
}

# =============================================================================
# NGINX
# =============================================================================

install_nginx() {
  if command -v nginx &>/dev/null; then
    ok "nginx ya instalado: $(nginx -v 2>&1)"
    return
  fi

  local deb_files=("$ASSETS_DIR/nginx/"*.deb)
  if [[ -f "${deb_files[0]:-}" ]]; then
    step "Instalando nginx desde assets (.deb)"
    dpkg -i "${deb_files[@]}" || apt-get install -f -y -qq || true
    ok "nginx instalado desde assets"
  else
    apt-get update -qq && apt-get install -y -qq nginx || true
  fi
}

# =============================================================================
# SQLCMD (mssql-tools18)
# =============================================================================

install_sqlcmd() {
  if command -v sqlcmd &>/dev/null; then
    ok "sqlcmd ya instalado"
    return
  fi

  local DB_DIR="$ASSETS_DIR/database"
  local sql_debs=("$DB_DIR/"mssql-tools18*.deb "$DB_DIR/"msodbcsql18*.deb)

  if [[ -f "${sql_debs[0]:-}" ]]; then
    step "Instalando sqlcmd desde assets (.deb)"

    # 1. Limpiar estado corrupto
    for pkg in msodbcsql18 mssql-tools18; do
      if dpkg -l "$pkg" 2>/dev/null | grep -q '^[a-z]'; then
        log "Limpiando $pkg..."
        rm -f /var/lib/dpkg/info/${pkg}.* 2>/dev/null || true
        dpkg --purge --force-depends "$pkg" 2>/dev/null || true
      fi
    done

    # 2. Instalar dependencias primero
    local odbc_deps=()
    for d in "$DB_DIR/"*.deb; do
      [[ "$(basename "$d")" != *mariadb* && "$(basename "$d")" != *msodbc* && "$(basename "$d")" != *mssql* ]] && odbc_deps+=("$d")
    done
    [[ ${#odbc_deps[@]} -gt 0 ]] && dpkg -i "${odbc_deps[@]}" 2>/dev/null || true

    # 3. Instalar msodbcsql y mssql-tools (con force-depends)
    log "Instalando drivers..."
    dpkg --force-depends -i "$DB_DIR/"msodbcsql18*.deb "$DB_DIR/"mssql-tools18*.deb 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
  fi

  # Symlink
  for p in "/opt/mssql-tools18/bin/sqlcmd" "/opt/mssql-tools/bin/sqlcmd"; do
    if [[ -x "$p" ]]; then
      ln -sf "$p" /usr/local/bin/sqlcmd 2>/dev/null || true
      ok "sqlcmd instalado"
      echo ""
      info "Para verificar la conexion a SQL Server manualmente:"
      info "  sqlcmd -C -S <server>,<port> -U <user> -P '<pass>' -d <db> -Q \"SELECT 1\""
      echo ""
      return
    fi
  done
}

# =============================================================================
# MARIADB CLIENT
# =============================================================================

install_mariadb_client() {
  if command -v mariadb &>/dev/null; then
    ok "mariadb-client ya instalado"
    return
  fi

  local DEB_DIR="$ASSETS_DIR/database"
  if ls "$DEB_DIR/"*mariadb*.deb &>/dev/null; then
    step "Instalando mariadb-client desde assets (.deb)"
    # Incluir las deps que NO matchean el glob *mariadb* (mysql-common,
    # libconfig-inifiles-perl). Sin ellas, en un install OFFLINE mariadb-client
    # queda "unpacked but not configured" y TRABA apt entero (no hay internet
    # para 'apt -f install'). dpkg -i con todas juntas resuelve el orden de deps.
    dpkg -i "$DEB_DIR/"mysql-common*.deb "$DEB_DIR/"libconfig-inifiles-perl*.deb "$DEB_DIR/"*mariadb*.deb 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
  else
    step "Instalando mariadb-client desde apt..."
    add-apt-repository universe -y -n 2>/dev/null || true
    apt-get update -qq && apt-get install -y -qq mariadb-client || true
  fi

  if command -v mariadb &>/dev/null; then
    echo ""
    info "Para verificar la conexion a MariaDB manualmente (te pide password):"
    info "  mariadb -h <server> -P <port> -u <user> -p --ssl-verify-server-cert=0 -e \"SELECT 1\""
    echo ""
  fi
}

# =============================================================================
# MAIN
# =============================================================================

require_root
echo -e "\n========================================"
echo -e "  EB Deploy — Bootstrap (V3-STABLE)"
echo -e "========================================\n"

install_system_packages
install_dotnet
install_node
install_rar
install_nginx
install_sqlcmd
install_mariadb_client

# Auto-reparar dependencias pendientes. Los dpkg -i / --force-depends de arriba
# (sqlcmd/mssql-tools, mariadb-client) pueden dejar paquetes "unpacked but not
# configured", lo que TRABA apt para cualquier instalacion posterior (ej: el
# certbot de configure-letsencrypt fallaba con "Unmet dependencies").
# Nota: en un install 100% offline las deps faltantes deben estar en assets/;
# si hay internet, apt las baja aca.
step "Reparando dependencias pendientes (apt -f install)"
if apt-get install -f -y; then
  ok "Dependencias resueltas."
else
  warn "apt -f install no pudo completar (revisa conectividad o falta un .deb en assets/)."
fi

echo -e "\n========================================\n"
