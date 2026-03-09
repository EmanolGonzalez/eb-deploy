#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup-server.sh — Instalación y preparación completa del entorno
# Automatiza: dependencias, azcopy, config.env centralizado, scripts, nginx, systemd
# =============================================================================

CONFIG_FILE="/app/config/config.env"
SCRIPTS_DIR="/app/scripts"

log()  { echo -e "\033[1;34m==> $*\033[0m"; }
err()  { echo -e "\033[1;31mError: $*\033[0m" >&2; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

require_internet() {
  if ! command -v curl &>/dev/null; then
    err "No se encontró 'curl' en el sistema. Instálalo y vuelve a ejecutar el setup."
    exit 1
  fi

  local urls=(
    "https://deb.debian.org"
    "https://packages.microsoft.com"
    "https://aka.ms"
  )

  for url in "${urls[@]}"; do
    if curl -I --silent --fail --max-time 7 "$url" >/dev/null 2>&1; then
      ok "Conectividad a internet verificada (${url})."
      return
    fi
  done

  err "No se detecto conexion a internet en la VM. No se puede continuar con setup-server.sh."
  err "Verifica DNS, salida a internet y reglas de firewall/proxy, y vuelve a intentar."
  exit 1
}

escape_for_sed_replacement() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//&/\\&}"
  printf '%s' "$input"
}

# =============================================================================
# AZCOPY
# =============================================================================

install_azcopy() {
  if command -v azcopy &>/dev/null; then
    ok "azcopy ya instalado: $(azcopy --version 2>/dev/null | head -1)"
    return
  fi

  log "Instalando azcopy..."
  local arch download_url tmp_dir azcopy_bin

  arch="$(uname -m)"
  case "$arch" in
    x86_64)  download_url="https://aka.ms/downloadazcopy-v10-linux" ;;
    aarch64) download_url="https://aka.ms/downloadazcopy-v10-linux-arm64" ;;
    *)
      err "Arquitectura no soportada para instalación automática: $arch"
      err "Instala azcopy manualmente desde: https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10"
      exit 1
      ;;
  esac

  tmp_dir="$(mktemp -d /tmp/azcopy-install-XXXXXX)"
  log "Descargando azcopy ($arch)..."
  if ! curl -fsSL "$download_url" -o "$tmp_dir/azcopy.tar.gz"; then
    rm -rf "$tmp_dir"
    err "No se pudo descargar azcopy desde Microsoft."
    exit 1
  fi

  tar -xzf "$tmp_dir/azcopy.tar.gz" -C "$tmp_dir"
  azcopy_bin="$(find "$tmp_dir" -name "azcopy" -type f | head -1 || true)"

  if [[ -z "$azcopy_bin" ]]; then
    rm -rf "$tmp_dir"
    err "No se encontró el binario azcopy después de extraer."
    exit 1
  fi

  mv "$azcopy_bin" /usr/local/bin/azcopy
  chmod +x /usr/local/bin/azcopy
  rm -rf "$tmp_dir"

  ok "azcopy instalado: $(azcopy --version 2>/dev/null | head -1)"
}

# =============================================================================
# CONFIGURACIÓN CENTRALIZADA
# =============================================================================

write_config_env() {
  local storage_account="$1"
  local container_name="$2"
  local base_url="$3"
  local scripts_base_url="$4"
  local nginx_server_name="${5:-}"
  local backend_health_endpoint="${6:-}"
  local db_connection_string="${7:-}"

  mkdir -p /app/config
  cat > "$CONFIG_FILE" <<EOF
# =============================================================================
# /app/config/config.env — Configuración centralizada del sistema de deploy
# Generado por setup-server.sh el $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

CONFIG_VERSION="1"

# --- CRÍTICAS (obligatorias) ---
STORAGE_ACCOUNT="${storage_account}"
CONTAINER_NAME="${container_name}"
BASE_URL="${base_url}"

# --- SCRIPTS ---
# URL base raw de GitHub. Usado por ops-menu.sh al actualizar scripts.
SCRIPTS_BASE_URL="${scripts_base_url}"

# --- OPCIONALES ---
NGINX_SERVER_NAME="${nginx_server_name}"
BACKEND_HEALTH_ENDPOINT="${backend_health_endpoint}"

# --- SECRETAS ---
DB_CONNECTION_STRING="${db_connection_string}"
EOF

  chmod 600 "$CONFIG_FILE"
  ok "config.env escrito: $CONFIG_FILE"
}

migrate_legacy_config() {
  # Migra automáticamente la configuración dispersa de archivos .txt/storage.conf
  # hacia el nuevo config.env unificado.
  local storage_conf="/app/config/storage.conf"
  local nginx_name_file="/app/config/nginx-server-name.txt"
  local health_file="/app/config/backend-health-endpoint.txt"
  local found=false

  local storage_account="" container_name="" base_url=""
  local nginx_server_name="" backend_health_endpoint=""

  if [[ -f "$storage_conf" ]]; then
    found=true
    # shellcheck source=/dev/null
    source "$storage_conf"
    storage_account="${STORAGE_ACCOUNT:-}"
    container_name="${CONTAINER_NAME:-}"
    base_url="${BASE_URL:-}"
    log "Migración: storage.conf (account=${storage_account}, container=${container_name})"
  fi

  if [[ -f "$nginx_name_file" ]]; then
    nginx_server_name="$(tr -d '\n' < "$nginx_name_file")"
    if [[ -n "$nginx_server_name" ]]; then
      found=true
      log "Migración: nginx-server-name.txt (${nginx_server_name})"
    fi
  fi

  if [[ -f "$health_file" ]]; then
    backend_health_endpoint="$(tr -d '\n' < "$health_file")"
    if [[ -n "$backend_health_endpoint" ]]; then
      found=true
      log "Migración: backend-health-endpoint.txt (${backend_health_endpoint})"
    fi
  fi

  if [[ "$found" == true ]]; then
    # SCRIPTS_BASE_URL y DB_CONNECTION_STRING no existían antes — migrar si hay
    local scripts_base_url="" db_connection_string=""
    read -rp "URL base raw de GitHub para scripts (Enter para dejarlo vacío por ahora): " scripts_base_url

    # Migrar db-connection.txt si existe
    local db_file="/app/config/db-connection.txt"
    if [[ -f "$db_file" ]]; then
      db_connection_string="$(cat "$db_file")"
      [[ -n "$db_connection_string" ]] && log "Migración: db-connection.txt → DB_CONNECTION_STRING"
    fi

    write_config_env "$storage_account" "$container_name" "$base_url" \
      "$scripts_base_url" "$nginx_server_name" "$backend_health_endpoint" "$db_connection_string"
    log "Migración completada. Los archivos heredados se conservan como respaldo."
    return 0
  fi

  return 1  # No había nada que migrar
}

setup_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "config.env encontrado en $CONFIG_FILE. Cargando..."
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    return
  fi

  log "No se encontró config.env. Buscando configuración heredada para migrar..."
  if migrate_legacy_config; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    return
  fi

  # Primera instalación: configuración interactiva completa
  log "Configurando acceso a Azure Blob Storage..."
  local storage_account container_name base_url scripts_base_url

  read -rp "Azure Storage Account name: " storage_account
  if [[ -z "$storage_account" ]]; then
    err "Storage Account es obligatorio."
    exit 1
  fi

  read -rp "Azure Container Name: " container_name
  if [[ -z "$container_name" ]]; then
    err "Container Name es obligatorio."
    exit 1
  fi

  base_url="https://${storage_account}.blob.core.windows.net/${container_name}"
  log "BASE_URL: $base_url"

  read -rp "URL base raw de GitHub para scripts (ej: https://raw.githubusercontent.com/usuario/repo/main): " scripts_base_url

  write_config_env "$storage_account" "$container_name" "$base_url" "$scripts_base_url"
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

# =============================================================================
# NGINX
# =============================================================================

resolve_server_name() {
  SERVER_NAME_VALUE="${NGINX_SERVER_NAME:-}"

  if [[ -n "$SERVER_NAME_VALUE" ]]; then
    log "Nginx server_name desde config.env: $SERVER_NAME_VALUE"
    return
  fi

  SERVER_NAME_VALUE="_"
  read -rp "¿Deseas configurar dominio/subdominio para Nginx? [y/N]: " use_domain
  if [[ "$use_domain" =~ ^[Yy]$ ]]; then
    read -rp "Dominio(s) (separados por espacio): " domain_value
    if [[ -n "$domain_value" ]]; then
      SERVER_NAME_VALUE="$domain_value"
      # Persistir en config.env
      if [[ -f "$CONFIG_FILE" ]]; then
        sed -i "s|^NGINX_SERVER_NAME=.*|NGINX_SERVER_NAME=\"${domain_value}\"|" "$CONFIG_FILE"
        log "NGINX_SERVER_NAME actualizado en config.env"
      fi
    fi
  fi
}

# =============================================================================
# DESCARGA DE SCRIPTS
# =============================================================================

download_scripts_fallback() {
  # Se usa solo si fetch-all.sh falla o no se puede descargar
  local base_url="$1"
  local scripts=(
    ops-menu.sh install.sh update.sh rollback.sh uninstall.sh
    healthcheck.sh status.sh set-db-connection.sh set-health-endpoint.sh
    configure-internal-https.sh setup-server.sh release.sh
  )
  log "Descargando scripts directamente (fallback)..."
  for script in "${scripts[@]}"; do
    if wget -q -O "$script" "$base_url/$script"; then
      chmod +x "$script"
    else
      err "No se pudo descargar $script desde $base_url"
      return 1
    fi
  done
  ok "Todos los scripts descargados (fallback)."
}

# =============================================================================
# MAIN
# =============================================================================

require_root
require_internet

# 1. Sistema base
log "Actualizando sistema e instalando dependencias base..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl git wget nginx unrar tar
ok "Dependencias base instaladas."

# 2. Node.js 20 LTS
if ! command -v node &>/dev/null || [[ "$(node -v 2>/dev/null)" != v20* ]]; then
  log "Instalando Node.js 20 LTS..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null
  apt-get install -y -qq nodejs
fi
ok "Node.js: $(node -v)"

# 3. .NET 9 SDK
if ! command -v dotnet &>/dev/null || ! dotnet --list-sdks 2>/dev/null | grep -q '^9\.'; then
  log "Instalando .NET 9 SDK..."
  DOTNET_INSTALL="/tmp/dotnet-install-$$.sh"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$DOTNET_INSTALL"
  chmod +x "$DOTNET_INSTALL"
  "$DOTNET_INSTALL" --channel 9.0 --install-dir /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
  rm -f "$DOTNET_INSTALL"
fi
ok ".NET: $(dotnet --version)"

# 4. sqlcmd (mssql-tools18)
install_sqlcmd() {
  if command -v sqlcmd &>/dev/null; then
    ok "sqlcmd ya instalado: $(sqlcmd -? 2>/dev/null | head -1 || echo 'ok')"
    return
  fi

  log "Instalando sqlcmd (mssql-tools18)..."

  # Importar clave GPG de Microsoft
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg

  # Detectar distro y versión para elegir el repositorio correcto
  local distro version
  # shellcheck source=/dev/null
  source /etc/os-release
  distro="${ID}"          # ubuntu / debian
  version="${VERSION_ID}" # 22.04 / 12 / etc.

  local repo_url="https://packages.microsoft.com/config/${distro}/${version}/prod.list"
  if ! curl -fsSL "$repo_url" -o /etc/apt/sources.list.d/mssql-release.list; then
    warn "No se pudo agregar el repositorio de Microsoft para ${distro} ${version}."
    warn "sqlcmd no estará disponible. Instálalo manualmente si es necesario."
    return
  fi

  apt-get update -qq
  ACCEPT_EULA=Y apt-get install -y -qq mssql-tools18 unixodbc-dev

  # Agregar al PATH del sistema para todos los usuarios
  echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' \
    > /etc/profile.d/mssql-tools.sh
  chmod +x /etc/profile.d/mssql-tools.sh

  # Disponible en la sesión actual también
  export PATH="$PATH:/opt/mssql-tools18/bin"

  ok "sqlcmd instalado: $(sqlcmd -? 2>/dev/null | head -1 || echo 'ok')"
}

install_sqlcmd

# 6. azcopy
install_azcopy

# 7. Nginx
log "Habilitando nginx..."
systemctl enable --now nginx
ok "nginx activo."

# 8. Estructura de directorios
log "Creando estructura /app/..."
mkdir -p "$SCRIPTS_DIR" /app/releases /app/config
ok "Directorios creados."

# 9. Configuración centralizada
setup_config

# 10. Descarga de scripts (fetch-all efímero)
cd "$SCRIPTS_DIR"

SCRIPTS_URL="${SCRIPTS_BASE_URL:-}"
if [[ -z "$SCRIPTS_URL" ]]; then
  read -rp "URL base raw de GitHub para scripts: " SCRIPTS_URL
fi

FETCH_TMP="$(mktemp /tmp/fetch-all-XXXXXX.sh)"
trap 'rm -f "$FETCH_TMP"' EXIT

log "Descargando scripts vía fetch-all (efímero)..."
if wget -q -O "$FETCH_TMP" "$SCRIPTS_URL/fetch-all.sh" 2>/dev/null \
    && grep -q '^#!/' "$FETCH_TMP" 2>/dev/null; then
  chmod +x "$FETCH_TMP"
  if ! bash "$FETCH_TMP" "$SCRIPTS_URL"; then
    err "fetch-all.sh terminó con error. Usando descarga directa..."
    download_scripts_fallback "$SCRIPTS_URL"
  fi
else
  err "No se pudo obtener fetch-all.sh desde $SCRIPTS_URL. Usando descarga directa..."
  download_scripts_fallback "$SCRIPTS_URL"
fi
# El trap elimina FETCH_TMP automáticamente al salir

# 9. Configuración de Nginx
if [[ ! -f /etc/nginx/sites-available/app ]]; then
  resolve_server_name
  log "Configurando Nginx..."
  cat > /etc/nginx/sites-available/app <<'NGINXEOF'
server {
    listen 80;
    server_name __SERVER_NAME__;
    root /app/frontend/current;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXEOF
  ESCAPED_SERVER_NAME="$(escape_for_sed_replacement "$SERVER_NAME_VALUE")"
  sed -i "s/__SERVER_NAME__/${ESCAPED_SERVER_NAME}/" /etc/nginx/sites-available/app
  ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
  ok "Nginx configurado."
fi

# 11. Servicio systemd backend
if [[ ! -f /etc/systemd/system/backend.service ]]; then
  log "Configurando servicio systemd backend..."
  cat > /etc/systemd/system/backend.service <<'SYSTEMDEOF'
[Unit]
Description=Backend .NET API Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dotnet /app/backend/current/Api.dll
WorkingDirectory=/app/backend/current
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://+:5000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMDEOF
  systemctl daemon-reload
  systemctl enable backend
  ok "Servicio backend configurado."
fi

log "Servidor preparado."
log "  Menú de operaciones : bash $SCRIPTS_DIR/ops-menu.sh"
log "  Instalar componente : bash $SCRIPTS_DIR/install.sh"
