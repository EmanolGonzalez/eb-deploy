#!/usr/bin/env bash
set -e

# =============================================================================
# setup-server.sh — Instalación y preparación completa del entorno
# Automatiza la instalación de dependencias, configuración de servicios y despliegue inicial
# =============================================================================

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

NGINX_SERVER_NAME_FILE="/app/config/nginx-server-name.txt"

download_scripts_directly() {
  local base_url="$1"
  local scripts=(ops-menu.sh install.sh update.sh rollback.sh uninstall.sh healthcheck.sh status.sh set-db-connection.sh set-health-endpoint.sh configure-internal-https.sh setup-server.sh)

  log "Descargando scripts directamente (fallback)..."
  for script in "${scripts[@]}"; do
    wget -q -O "$script" "$base_url/$script" || {
      err "No se pudo descargar $script desde $base_url"
      return 1
    }
    chmod +x "$script"
  done
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

escape_for_sed_replacement() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//&/\\&}"
  printf '%s' "$input"
}

resolve_server_name() {
  SERVER_NAME_VALUE="_"

  if [[ -f "$NGINX_SERVER_NAME_FILE" ]]; then
    SERVER_NAME_VALUE="$(cat "$NGINX_SERVER_NAME_FILE")"
    if [[ -n "$SERVER_NAME_VALUE" ]]; then
      log "Server name cargado desde $NGINX_SERVER_NAME_FILE: $SERVER_NAME_VALUE"
      return
    fi
  fi

  read -rp "¿Deseas registrar dominio/subdominio para Nginx ahora? [y/N]: " use_domain
  if [[ "$use_domain" =~ ^[Yy]$ ]]; then
    read -rp "Ingresa dominio/subdominio (puedes poner varios separados por espacio): " domain_value
    if [[ -n "$domain_value" ]]; then
      SERVER_NAME_VALUE="$domain_value"
      mkdir -p /app/config
      printf '%s' "$SERVER_NAME_VALUE" > "$NGINX_SERVER_NAME_FILE"
      chmod 600 "$NGINX_SERVER_NAME_FILE"
      log "Server name guardado en $NGINX_SERVER_NAME_FILE"
    fi
  fi
}

# 1. Validar root
require_root

# 2. Actualizar sistema e instalar dependencias base
log "Actualizando sistema e instalando dependencias base..."
apt update && apt upgrade -y
apt install -y curl git wget nginx unrar

# 3. Instalar Node.js 20 LTS
if ! command -v node >/dev/null || [[ $(node -v) != v20* ]]; then
  log "Instalando Node.js 20 LTS..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# 4. Instalar .NET 9 SDK
if ! command -v dotnet >/dev/null || ! dotnet --list-sdks | grep -q 9.0; then
  log "Instalando .NET 9 SDK..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
  rm -f /tmp/dotnet-install.sh
  log ".NET 9 instalado: $(dotnet --version)"
fi

# 5. Habilitar y arrancar nginx
log "Habilitando y arrancando nginx..."
systemctl enable --now nginx

# 6. Crear estructura de carpetas
log "Creando estructura de carpetas en /app..."
mkdir -p /app/scripts /app/releases /app/config

# 7. Descargar fetch-all.sh y scripts de despliegue
read -rp "Introduce la URL base raw de GitHub (ej: https://raw.githubusercontent.com/usuario/repo/main): " SCRIPTS_BASE_URL
cd /app/scripts

FETCH_ALL_OK=0
if wget -q -O fetch-all.sh "${SCRIPTS_BASE_URL}/fetch-all.sh"; then
  chmod +x fetch-all.sh
  log "Descargando scripts con fetch-all.sh (ops-menu.sh primero)..."
  if bash fetch-all.sh "$SCRIPTS_BASE_URL"; then
    FETCH_ALL_OK=1
  else
    err "fetch-all.sh falló. Se usará descarga directa."
  fi
else
  err "No se pudo descargar fetch-all.sh. Se usará descarga directa."
fi

if [[ "$FETCH_ALL_OK" -ne 1 ]]; then
  download_scripts_directly "$SCRIPTS_BASE_URL"
fi

# 8. Configuración de Nginx (plantilla básica, personalizar según necesidad)
if [[ ! -f /etc/nginx/sites-available/app ]]; then
  resolve_server_name
  log "Configurando Nginx para servir frontend y backend..."
  cat > /etc/nginx/sites-available/app <<'EOF'
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
EOF
  ESCAPED_SERVER_NAME="$(escape_for_sed_replacement "$SERVER_NAME_VALUE")"
  sed -i "s/__SERVER_NAME__/${ESCAPED_SERVER_NAME}/" /etc/nginx/sites-available/app
  ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
fi

# 9. Configuración de systemd para backend (plantilla básica)
if [[ ! -f /etc/systemd/system/backend.service ]]; then
  log "Configurando systemd para backend..."
  cat > /etc/systemd/system/backend.service <<EOF
[Unit]
Description=Backend .NET API Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dotnet /app/backend/current/publish/api.dll
WorkingDirectory=/app/backend/current/publish
EnvironmentFile=-/etc/xproyect-api.env
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable backend
fi

# 10. Configuración de Azure Storage
CONFIG_FILE="/app/config/storage.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Configurando acceso a Azure Blob Storage..."
  read -rp "Enter Azure Storage Account: " STORAGE_ACCOUNT
  read -rp "Enter Azure Container Name: " CONTAINER_NAME
  BASE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}"
  cat > "$CONFIG_FILE" <<EOF
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
CONTAINER_NAME="$CONTAINER_NAME"
BASE_URL="$BASE_URL"
EOF
  log "Configuración guardada en $CONFIG_FILE."
fi

log "Servidor preparado. Inicia con el menú técnico:"
log "  bash /app/scripts/ops-menu.sh"
log "Si prefieres flujo manual, ejecuta install.sh para cada componente:"
log "  bash /app/scripts/install.sh   # frontend"
log "  bash /app/scripts/install.sh   # backend"
