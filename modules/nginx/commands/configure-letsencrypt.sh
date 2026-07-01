#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/nginx/commands/configure-letsencrypt.sh
#
# HTTPS con certificado GRATUITO de Let's Encrypt — pensado para el server de
# DESARROLLO (la VM con dominio publico). Produccion sigue usando el HTTPS
# interno (configure-https.sh con cert self-signed/provisto).
#
# REQUISITOS (sin esto, Let's Encrypt NO emite):
#   1. Un dominio publico (FQDN) que resuelva a la IP de esta VM.
#      Si no tenes dominio propio, una VM de Azure tiene uno GRATIS:
#        <label>.<region>.cloudapp.azure.com  (VM -> Configuration -> DNS name).
#   2. Puerto 80 accesible desde internet: el challenge HTTP-01 de LE pega ahi.
#      (En Azure: abrir el 80 en el Network Security Group.)
#
# COMO funciona (mismo patron que configure-https):
#   - Saca el cert con certbot --standalone (para nginx unos segundos para
#     liberar el :80 durante el challenge; downtime minimo, aceptable en dev).
#   - Persiste NGINX_SERVER_NAME / NGINX_SSL_CERT / NGINX_SSL_KEY en config.env.
#   - Delega a setup-server.sh (NON_INTERACTIVE) que re-renderiza el vhost HTTPS.
#   - Instala renewal-hooks globales para que la renovacion automatica del timer
#     de certbot tambien pare/levante nginx sin intervencion.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/nginx-common.sh"

LE_LIVE_DIR="/etc/letsencrypt/live"
RENEWAL_HOOK_PRE="/etc/letsencrypt/renewal-hooks/pre/stop-nginx.sh"
RENEWAL_HOOK_POST="/etc/letsencrypt/renewal-hooks/post/start-nginx.sh"

require_root
load_config || true

# -----------------------------------------------------------------------------
# 1. Dominio — de config.env o interactivo. Let's Encrypt NO emite para IPs.
# -----------------------------------------------------------------------------
domain="${NGINX_SERVER_NAME:-_}"
if [[ -z "$domain" || "$domain" == "_" ]]; then
  read -rp "Dominio publico para Let's Encrypt (ej: dev-ema.eastus.cloudapp.azure.com): " domain
fi

if [[ -z "$domain" ]]; then
  err "El dominio es obligatorio para Let's Encrypt."
  exit 1
fi

# Rechazar IP pelada y nombres sin punto: un cert TLS certifica un NOMBRE, no
# una IP. Una CA publica no puede validar la propiedad de una IP -> no emite.
if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  err "'$domain' es una IP. Let's Encrypt NO emite certificados para IPs."
  err "Necesitas un dominio publico (FQDN). En Azure podes usar el gratuito:"
  err "  <label>.<region>.cloudapp.azure.com  (se configura en el portal)."
  exit 1
fi
if [[ "$domain" != *.* ]]; then
  err "'$domain' no parece un FQDN valido (le falta el dominio)."
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Email de registro (recomendado: LE avisa vencimientos y revocaciones).
# -----------------------------------------------------------------------------
read -rp "Email para avisos de Let's Encrypt (Enter para omitir): " le_email
if [[ -n "$le_email" ]]; then
  email_flag=(-m "$le_email")
else
  email_flag=(--register-unsafely-without-email)
fi

# -----------------------------------------------------------------------------
# 3. Staging — para PROBAR sin gastar el rate limit de produccion de LE.
# -----------------------------------------------------------------------------
staging_flag=()
read -rp "Usar entorno STAGING de Let's Encrypt (para probar)? [y/N]: " use_staging
if [[ "$use_staging" =~ ^[Yy]$ ]]; then
  staging_flag=(--staging)
  warn "Modo STAGING: el cert NO sera de confianza en el browser (solo valida el flujo)."
fi

# -----------------------------------------------------------------------------
# 4. certbot — instalar si falta (dev con internet).
# -----------------------------------------------------------------------------
if ! command -v certbot &>/dev/null; then
  step "Instalando certbot (apt)..."
  if ! { apt-get update -qq && apt-get install -y -qq certbot; }; then
    err "No se pudo instalar certbot. Verifica conexion a internet en la VM."
    exit 1
  fi
  ok "certbot instalado."
fi

# -----------------------------------------------------------------------------
# 5. Renewal hooks globales — paran/levantan nginx en CADA renovacion del timer.
#    (--standalone necesita el :80 libre; estos hooks lo garantizan sin manos.)
# -----------------------------------------------------------------------------
mkdir -p "$(dirname "$RENEWAL_HOOK_PRE")" "$(dirname "$RENEWAL_HOOK_POST")"
cat > "$RENEWAL_HOOK_PRE" <<'HOOK'
#!/usr/bin/env bash
# Generado por 'deploy nginx configure-letsencrypt'. Libera el :80 para el challenge.
systemctl stop nginx
HOOK
cat > "$RENEWAL_HOOK_POST" <<'HOOK'
#!/usr/bin/env bash
# Generado por 'deploy nginx configure-letsencrypt'. Levanta nginx tras renovar.
systemctl start nginx
HOOK
chmod +x "$RENEWAL_HOOK_PRE" "$RENEWAL_HOOK_POST"
ok "Renewal hooks instalados (renovacion automatica sin intervencion)."

# -----------------------------------------------------------------------------
# 6. Emitir el certificado. --standalone con pre/post-hook para esta corrida.
# -----------------------------------------------------------------------------
step "Solicitando certificado a Let's Encrypt para $domain..."
log "nginx se detiene unos segundos durante el challenge HTTP-01."
# --standalone necesita el :80 libre. Paramos nginx explicitamente y lo
# levantamos SIEMPRE despues (exito o error) para no dejar el sitio caido.
# La renovacion automatica usa los renewal-hooks GLOBALES de arriba, por eso
# NO pasamos --pre/--post/--deploy-hook: si se guardaran por-cert, el reload
# correria con nginx apagado y fallaria en cada renovacion.
systemctl stop nginx || true
set +e
certbot certonly --standalone \
  --non-interactive --agree-tos \
  "${email_flag[@]}" \
  "${staging_flag[@]}" \
  -d "$domain"
certbot_rc=$?
set -e
systemctl start nginx || true

if [[ "$certbot_rc" -ne 0 ]]; then
  err "certbot fallo. Causas tipicas:"
  err "  - El dominio '$domain' no resuelve a la IP publica de esta VM (revisa DNS)."
  err "  - El puerto 80 no esta abierto desde internet (NSG de Azure / firewall)."
  err "  - Alcanzaste el rate limit de LE (proba con STAGING)."
  exit 1
fi

cert_path="$LE_LIVE_DIR/$domain/fullchain.pem"
key_path="$LE_LIVE_DIR/$domain/privkey.pem"
if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
  err "certbot reporto exito pero no encuentro los archivos en $LE_LIVE_DIR/$domain/"
  exit 1
fi
ok "Certificado emitido: $cert_path"

# -----------------------------------------------------------------------------
# 7. Persistir en config.env (UNICA fuente de verdad) y re-renderizar nginx.
# -----------------------------------------------------------------------------
update_config_value "NGINX_SERVER_NAME" "$domain"
update_config_value "NGINX_SSL_CERT" "$cert_path"
update_config_value "NGINX_SSL_KEY" "$key_path"
ok "config.env actualizado (server_name + paths del cert)."

log "Aplicando via setup-server.sh (NON_INTERACTIVE)..."
NON_INTERACTIVE=1 bash /app/deploy/setup/setup-server.sh

echo
ok "HTTPS con Let's Encrypt activo en https://${domain}/"
log "Validar    : curl -I https://${domain}/"
log "Renovacion : automatica (timer de certbot). Probar en seco: certbot renew --dry-run"
