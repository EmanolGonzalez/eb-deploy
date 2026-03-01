#!/usr/bin/env bash
set -e

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

require_root

read -rp "Subdominio interno (ej: app.interno.empresa.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  err "Domain is required."
  exit 1
fi

read -rp "Ruta certificado (.crt/.pem): " CERT_FILE
read -rp "Ruta llave privada (.key): " KEY_FILE

if [[ -z "$CERT_FILE" || -z "$KEY_FILE" ]]; then
  err "Certificate and key paths are required."
  exit 1
fi

if [[ ! -f "$CERT_FILE" ]]; then
  err "Certificate file not found: $CERT_FILE"
  exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
  err "Key file not found: $KEY_FILE"
  exit 1
fi

read -rp "Ruta frontend (default: /app/frontend/current/dist): " FRONTEND_ROOT
FRONTEND_ROOT="${FRONTEND_ROOT:-/app/frontend/current/dist}"

read -rp "Upstream backend (default: http://127.0.0.1:5000): " BACKEND_UPSTREAM
BACKEND_UPSTREAM="${BACKEND_UPSTREAM:-http://127.0.0.1:5000}"

SITE_NAME="app"
NGINX_SITE_FILE="/etc/nginx/sites-available/${SITE_NAME}"

log "Generating nginx site config: $NGINX_SITE_FILE"
cat > "$NGINX_SITE_FILE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    root ${FRONTEND_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass ${BACKEND_UPSTREAM};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sfn "$NGINX_SITE_FILE" "/etc/nginx/sites-enabled/${SITE_NAME}"
rm -f /etc/nginx/sites-enabled/default

log "Validating nginx config..."
nginx -t

log "Reloading nginx..."
systemctl reload nginx

log "Done. HTTPS configured for ${DOMAIN}."
