#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup-server.sh — Server configuration after bootstrap
# Assumes dependencies are already installed (via bootstrap.sh).
# Configures: config.env (con todas las vars del backend), nginx, systemd.
#
# Seguridad: config.env es la UNICA fuente de secretos.
# Se carga via systemd EnvironmentFile. appsettings.json NO se modifica.
# =============================================================================

CONFIG_FILE="/app/config/config.env"
DEPLOY_DIR="/app/deploy"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "$DEPLOY_BASE/core/logger.sh" ]] && source "$DEPLOY_BASE/core/logger.sh"
[[ -f "$DEPLOY_BASE/core/config.sh" ]] && source "$DEPLOY_BASE/core/config.sh"
[[ -f "$DEPLOY_BASE/core/system.sh" ]] && source "$DEPLOY_BASE/core/system.sh"

# Version esperada del schema de config.env. Subir cuando se agregan o
# eliminan variables incompatibles. check_config_version() avisa si el
# config.env en disco esta desactualizado.
EXPECTED_CONFIG_VERSION="4"

# =============================================================================
# SERVICE USER — dedicated non-root user for the backend
# =============================================================================

SERVICE_USER="app-backend"
SERVICE_GROUP="app-backend"

create_service_user() {
  if id "$SERVICE_USER" &>/dev/null; then
    ok "Usuario $SERVICE_USER ya existe (uid=$(id -u "$SERVICE_USER"))."
    return
  fi
  log "Creando usuario de servicio $SERVICE_USER..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
  ok "Usuario $SERVICE_USER creado (system, no-home, nologin)."
}

# =============================================================================
# BOOTSTRAP (dependencies from assets/)
# =============================================================================

run_bootstrap() {
  local bootstrap_script="$DEPLOY_DIR/setup/bootstrap.sh"

  if [[ -f "$bootstrap_script" ]]; then
    step "Ejecutando bootstrap (instalacion desde assets locales)..."
    bash "$bootstrap_script"
    ok "Bootstrap completado."
  else
    warn "bootstrap.sh no encontrado en $DEPLOY_DIR"
    warn "Asegurate de que las dependencias esten instaladas antes de continuar."
  fi
}

# =============================================================================
# CONFIGURACION CENTRALIZADA — UNICO archivo con TODAS las vars
# =============================================================================

write_config_template() {
  mkdir -p /app/config
  cat > "$CONFIG_FILE" <<EOF
# =============================================================================
# /app/config/config.env — Configuracion centralizada del sistema de deploy
# Generado por setup-server.sh el $(date '+%Y-%m-%d %H:%M:%S')
#
# Este archivo es la UNICA fuente de secretos.
# Se carga via systemd EnvironmentFile en el servicio backend.
# appsettings.json NO debe contener secretos (tiene CHANGE_ME).
#
# Convencion .NET: __ = jerarquia JSON
# Ej: ConnectionStrings__MariaDB overrideea ConnectionStrings.MariaDB
#
# INSTRUCCIONES:
#   1. Reemplaza cada CHANGE_ME con el valor real.
#   2. Debes setear la cadena de conexion de MariaDB.
#   3. Guarda y cierra el editor. El script valida y continua.
# =============================================================================

CONFIG_VERSION="4"

# =============================================================================
# DEPLOY SYSTEM (usadas por los scripts de deploy)
# =============================================================================

# Dominio para Nginx. Default "_" acepta cualquier host.
# Ejemplo: "app.dominio.com"
NGINX_SERVER_NAME="_"

# Rutas del certificado SSL y la clave privada (opcionales).
# Si AMBAS estan definidas, nginx levanta HTTPS en 443 + redirect 80 -> 443.
# Si una o ambas estan vacias, nginx queda en HTTP plano (puerto 80).
# Usar el wizard: deploy nginx configure-https
NGINX_SSL_CERT=""
NGINX_SSL_KEY=""

# Endpoint de healthcheck del backend (opcional).
# Ejemplo: "http://localhost:5000/api/health"
BACKEND_HEALTH_ENDPOINT=""

# =============================================================================
# BACKEND ENVIRONMENT VARIABLES (inyectadas via systemd EnvironmentFile)
# El backend lee estas vars y overrideea appsettings.json automaticamente.
# =============================================================================

# --- DATABASE ---
# DB_PROVIDER: unico valor soportado es "MariaDB".
DB_PROVIDER="MariaDB"

# Cadena de conexion para MariaDB.
# Driver: MySqlConnector via Pomelo (UseMySql). El backend la usa TAL CUAL.
#
# Atributos y POR QUE se necesitan (servidores internos SIN SSL valido):
#   Server=host;Port=3307    -> OJO: el puerto por defecto del proyecto es 3307
#                               (no el 3306 estandar). Confirma el real.
#   Database=...;User=...;Password=... -> conexion y credenciales.
#   CharSet=utf8mb4          -> unicode completo; necesario para PII/acentos.
#   SslMode=Preferred        -> usa SSL si esta, SIN validar el cert -> anda en
#                               internos sin SSL. NUNCA uses Required/VerifyCA/
#                               VerifyFull: validan cert y FALLAN en internos.
#                               (SslMode=None tambien sirve: no intenta SSL.)
#   AllowPublicKeyRetrieval=False -> seguridad: no le pide la clave publica al server.
# Ejemplo: "Server=10.0.0.6;Port=3307;Database=ema;User=eb_app;Password=secret;CharSet=utf8mb4;SslMode=Preferred;AllowPublicKeyRetrieval=False;"
ConnectionStrings__MariaDB="CHANGE_ME"

# --- FRONTEND ---
# URL publica del frontend.
# Ejemplo: "http://app.dominio.com" o "http://localhost:5020"
FrontendProdUrl="CHANGE_ME"

# --- AUTH OIDC ---
# Authority del Identity Server.
# Ejemplo: "https://stste.signes30.com/securitytokenservice"
Authentication__Authority="CHANGE_ME"

# Audience (API name) del Identity Server.
# Ejemplo: "certified-delivery-api"
Authentication__Audience="CHANGE_ME"

# Server interno: si el Identity Server es HTTP (sin SSL valido), en Production
# el backend EXIGE que Authority sea HTTPS y NO ARRANCA al bajar el metadata.
# Descomenta esto para permitir Authority por HTTP en redes internas:
# Authentication__RequireHttpsMetadata="false"

# --- CRYPTOGRAPHY ---
# Clave RSA privada se lee directamente de /app/secrets/rsa-private-key.pem
# No se necesita variable de entorno. Para rotar: deploy system rotate-pem

# --- PII ENCRYPTION ---
# Clave HMAC (base64, 32+ bytes) para hashes de busqueda sobre columnas PII
# (Documento, CitizenNationalId, etc).
# CRITICA: si se pierde, las busquedas por hash NO matchean los datos historicos.
# NUNCA rotar sin re-hashear toda la data afectada (no hay backfill automatico).
# Generar manual: openssl rand -base64 32
# Si esta en CHANGE_ME, el setup ofrece autogenerar y muestra el valor para backup.
PiiEncryption__HashKeyBase64="CHANGE_ME"

# --- TRIBUNAL SERVICES ---
# NetworkScope: "Internal" o "External"
TribunalServices__NetworkScope="Internal"

# Servers del tribunal (hostnames base por ambiente). Completar al menos el par
# que coincide con NetworkScope arriba. Si NetworkScope=Internal, Servers__Internal__*
# es obligatorio; los External pueden quedar vacios.
# TribunalServices__Servers__Internal__Dev=
# TribunalServices__Servers__Internal__Prod=
# TribunalServices__Servers__External__Dev=
# TribunalServices__Servers__External__Prod=

# Credenciales del tribunal (descomentar y completar las que se usen)
# TribunalServices__Credentials__1__Username=
# TribunalServices__Credentials__1__Password=
# TribunalServices__Credentials__1__Secret=
# TribunalServices__Credentials__2__Username=
# TribunalServices__Credentials__2__Password=
# TribunalServices__Credentials__2__Secret=
# TribunalServices__Credentials__3__Username=
# TribunalServices__Credentials__3__Password=
# TribunalServices__Credentials__3__Secret=
# TribunalServices__Credentials__4__Username=
# TribunalServices__Credentials__4__Password=
# TribunalServices__Credentials__4__Secret=
# TribunalServices__Credentials__5__Username=
# TribunalServices__Credentials__5__Password=
# TribunalServices__Credentials__5__Secret=

# =============================================================================
# RUNTIME OVERRIDES (opcionales — tienen defaults en appsettings.json)
# Descomentar para overridear valores por defecto.
# =============================================================================

# Session__CookieTimeoutHours=1
# Session__CleanupIntervalMinutes=1
# Session__StaleThresholdMinutes=2

# RateLimiting__WindowMinutes=1
# RateLimiting__MaxRequests=100

# BackgroundJobs__DeliveryOrderTimeoutMinutes=10
# BackgroundJobs__DailyLogSnapshotIntervalMinutes=5

# Cache__MasterDataHours=6
# Cache__OfficeValidationHours=6
# Cache__BiometryTokenMinutes=15
# Cache__FeatureToggleMinutes=5

# HttpClients__NominatimTimeoutSeconds=10

# HealthChecks__PublisherPeriodSeconds=15
# HealthChecks__PublisherTimeoutSeconds=20

# SignalR__HubTimeoutSeconds=10
EOF

  chmod 600 "$CONFIG_FILE"
  ok "config.env escrito: $CONFIG_FILE"
}

detect_editor() {
  if [[ -n "${EDITOR:-}" ]] && command -v "$EDITOR" &>/dev/null; then
    printf '%s' "$EDITOR"
    return
  fi
  for candidate in nano vim vi; do
    if command -v "$candidate" &>/dev/null; then
      printf '%s' "$candidate"
      return
    fi
  done
  return 1
}

validate_config() {
  local mariadb frontend authority audience
  # Parser sin source — un valor con $(comando) NO se ejecuta.
  load_config || return 1
  mariadb="${ConnectionStrings__MariaDB:-}"
  frontend="${FrontendProdUrl:-}"
  authority="${Authentication__Authority:-}"
  audience="${Authentication__Audience:-}"

  local errors=()

  if [[ "$mariadb" == "CHANGE_ME" ]]; then
    errors+=("ConnectionStrings__MariaDB tiene 'CHANGE_ME'. Reemplazalo por el valor real.")
  fi
  if [[ -z "$mariadb" ]]; then
    errors+=("Debes setear ConnectionStrings__MariaDB.")
  fi
  if [[ "$frontend" == "CHANGE_ME" ]]; then
    errors+=("FrontendProdUrl tiene CHANGE_ME. Reemplazalo por la URL real.")
  fi
  if [[ "$authority" == "CHANGE_ME" ]]; then
    errors+=("Authentication__Authority tiene CHANGE_ME. Reemplazalo por la URL del Identity Server.")
  fi
  if [[ "$audience" == "CHANGE_ME" ]]; then
    errors+=("Authentication__Audience tiene CHANGE_ME. Reemplazalo por el nombre del API.")
  fi

  # SSL / trust contra servers internos sin cert valido (funcion compartida en
  # core/config.sh — mismo aviso aca y en 'system edit-config'). No bloquea.
  warn_db_ssl_config

  if [[ ${#errors[@]} -gt 0 ]]; then
    echo
    err "config.env tiene problemas:"
    for e in "${errors[@]}"; do
      err "  - $e"
    done
    return 1
  fi

  return 0
}

edit_config_loop() {
  local editor
  if ! editor="$(detect_editor)"; then
    err "No se encontro un editor (probaste \$EDITOR, nano, vim, vi)."
    err "Edita manualmente $CONFIG_FILE y volve a correr setup."
    exit 1
  fi

  while true; do
    log "Abriendo $CONFIG_FILE con $editor..."
    "$editor" "$CONFIG_FILE"

    if validate_config; then
      ok "config.env valido."
      return 0
    fi

    echo
    read -rp "Reabrir el editor para corregir? [Y/n]: " retry
    if [[ "$retry" =~ ^[Nn]$ ]]; then
      err "Setup abortado. Corregi $CONFIG_FILE y volve a correr 'deploy system setup'."
      exit 1
    fi
  done
}

generate_pii_hash_key() {
  # Si PiiEncryption__HashKeyBase64 es CHANGE_ME o esta vacia, autogenerar y
  # persistir en config.env. Mostrar el valor — el operador DEBE respaldarlo
  # fuera del server (si lo pierde, las busquedas por hash se rompen).
  local current="${PiiEncryption__HashKeyBase64:-}"
  if [[ -n "$current" && "$current" != "CHANGE_ME" ]]; then
    log "PiiEncryption__HashKeyBase64 ya esta configurada."
    return
  fi

  if ! command -v openssl &>/dev/null; then
    warn "openssl no disponible. Generala manualmente y editala en config.env:"
    warn "  PiiEncryption__HashKeyBase64=<openssl rand -base64 32>"
    return
  fi

  local new_key
  new_key="$(openssl rand -base64 32)"
  update_config_value "PiiEncryption__HashKeyBase64" "$new_key"
  PiiEncryption__HashKeyBase64="$new_key"

  echo
  warn "=================================================================="
  warn "  PiiEncryption__HashKeyBase64 fue AUTOGENERADA."
  warn "  Valor: $new_key"
  warn ""
  warn "  RESPALDA esta clave FUERA del server (vault, gestor de secretos)."
  warn "  Si se pierde y la DB tiene hashes calculados con ella, las"
  warn "  busquedas por hash dejan de funcionar PERMANENTEMENTE."
  warn "  NUNCA rotar sin re-hashear toda la data afectada."
  warn "=================================================================="
  echo
}

generate_rsa_key() {
  local pem_path="/app/secrets/rsa-private-key.pem"
  if [[ -f "$pem_path" ]]; then
    log "Clave RSA existente encontrada en $pem_path."
    # Reaplica ownership por si el archivo quedo de root de una instalacion previa.
    chown "$SERVICE_USER:$SERVICE_GROUP" "$pem_path"
    chmod 400 "$pem_path"
    return
  fi
  if ! command -v openssl &>/dev/null; then
    warn "openssl no disponible. Genera la clave manualmente en $pem_path"
    return
  fi
  mkdir -p "$(dirname "$pem_path")"
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$pem_path"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$pem_path"
  chmod 400 "$pem_path"
  ok "Clave RSA generada en $pem_path (owner=$SERVICE_USER, chmod 400)."
}

config_has_placeholders() {
  [[ -f "$CONFIG_FILE" ]] || return 1
  grep -q 'CHANGE_ME' "$CONFIG_FILE"
}

setup_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Primera instalacion: generando plantilla de config.env..."
    write_config_template
    chmod 600 "$CONFIG_FILE"
    ok "Plantilla creada en $CONFIG_FILE"
  else
    log "config.env existente en $CONFIG_FILE"
  fi

  if [[ -n "${NON_INTERACTIVE:-}" ]]; then
    log "Modo NON_INTERACTIVE: salteando edicion de config.env."
  else
    echo
    log "Podes editar config.env ahora, o saltearlo y editarlo despues con:"
    log "  nano $CONFIG_FILE"
    log "  (o re-corre: deploy system setup)"
    echo
    read -rp "Editar config.env ahora? [Y/n]: " edit_now
    if [[ "$edit_now" =~ ^[Nn]$ ]]; then
      warn "Saltado el editor. El backend NO va a arrancar hasta que completes config.env."
    else
      edit_config_loop
    fi
  fi

  generate_rsa_key

  # Cargar config para tener PiiEncryption__HashKeyBase64 en scope antes
  # de decidir si autogenerar.
  load_config

  generate_pii_hash_key

  check_config_version
}

# =============================================================================
# CONFIG VERSION CHECK
# =============================================================================
check_config_version() {
  local current="${CONFIG_VERSION:-}"
  if [[ -z "$current" ]]; then
    warn "CONFIG_VERSION no esta definido en config.env."
    warn "Posiblemente sea un archivo viejo. Esperado: $EXPECTED_CONFIG_VERSION"
    return
  fi
  if [[ "$current" == "$EXPECTED_CONFIG_VERSION" ]]; then
    return
  fi
  if (( current < EXPECTED_CONFIG_VERSION )); then
    warn "config.env es version $current; este script espera $EXPECTED_CONFIG_VERSION."
    warn "Hay variables nuevas en el template. Compara contra write_config_template()"
    warn "o regenera el archivo (cuidado: pierdes valores actuales)."
  else
    warn "config.env es version $current; este script es $EXPECTED_CONFIG_VERSION."
    warn "Probable que el script este desactualizado vs el archivo."
  fi
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
      if [[ -f "$CONFIG_FILE" ]]; then
        sed -i "s|^NGINX_SERVER_NAME=.*|NGINX_SERVER_NAME=\"${domain_value}\"|" "$CONFIG_FILE"
        log "NGINX_SERVER_NAME actualizado en config.env"
      fi
    fi
  fi
}

# =============================================================================
# IDEMPOTENT FILE WRITE — drift detection
# =============================================================================
# Escribe $expected al target solo si difiere del actual. Backup con timestamp
# del archivo anterior. Return 1 si hubo cambio (caller decide que hacer),
# 0 si ya estaba sincronizado.
apply_file_if_drifted() {
  local target="$1"
  local expected="$2"
  local label="${3:-$target}"

  if [[ ! -f "$target" ]]; then
    printf '%s\n' "$expected" > "$target"
    ok "$label creado."
    return 1
  fi

  if diff -q <(printf '%s\n' "$expected") "$target" >/dev/null 2>&1; then
    ok "$label sincronizado (sin cambios)."
    return 0
  fi

  local backup="${target}.bak.$(date '+%Y%m%d-%H%M%S')"
  cp -p "$target" "$backup"
  warn "$label difiere — backup en $backup"
  printf '%s\n' "$expected" > "$target"
  ok "$label actualizado."
  return 1
}

# =============================================================================
# UNIT / CONFIG RENDERERS
# =============================================================================

render_backend_service_unit() {
  cat <<SYSTEMDEOF
[Unit]
Description=Backend .NET API Service
After=network.target

# Anti crash-loop de migraciones: si el arranque falla (ej: una migracion EF),
# systemd reintenta como mucho StartLimitBurst veces en StartLimitIntervalSec y
# luego se DETIENE (failed) en vez de loopear infinito pisando la migracion.
StartLimitIntervalSec=200
StartLimitBurst=4

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
ExecStart=/usr/bin/dotnet /app/backend/current/Api.dll
WorkingDirectory=/app/backend/current

# EnvironmentFile carga TODAS las variables de config.env al proceso.
# systemd lo lee como root ANTES de bajar privilegios a User=, asi que
# config.env puede seguir siendo root:root chmod 600.
EnvironmentFile=/app/config/config.env

Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://+:5000

# SkiaSharp/fontconfig: con ProtectSystem=strict + usuario sin home, fontconfig
# no tiene donde escribir su cache ("Fontconfig error: No writable cache
# directories"). PrivateTmp=yes da un /tmp privado escribible; lo usamos como
# cache asi el render de texto de la cedula no se degrada.
Environment=XDG_CACHE_HOME=/tmp

# --- Filesystem isolation ---
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/app/deploy/storage

# --- Kernel/syscall hardening (NO usar MemoryDenyWriteExecute - rompe JIT .NET) ---
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

Restart=always
# 15s (no 5): mayor que el arranque+migracion (~10-18s). Evita que un reinicio
# pise una migracion EF en curso — la causa de la carrera "Duplicate column".
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMDEOF
}

render_nginx_site_config() {
  # Heredoc unquoted: expande ${SERVER_NAME_VALUE} y ${NGINX_SSL_*} de bash.
  # Las variables de nginx ($host, $uri, etc) van escapadas con \ para que
  # queden literales en la salida.
  local ssl_cert="${NGINX_SSL_CERT:-}"
  local ssl_key="${NGINX_SSL_KEY:-}"

  cat <<MAPEOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

MAPEOF

  if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
    # HTTPS: 443 con TLS + redirect 80 -> 443.
    cat <<HTTPSEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAME_VALUE};
    server_tokens off;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${SERVER_NAME_VALUE};
    server_tokens off;

    ssl_certificate     ${ssl_cert};
    ssl_certificate_key ${ssl_key};

    # TLS profile: Mozilla intermediate, ECDHE-only (sin DHE = sin dhparam).
    # Todos los ciphers tienen forward secrecy y son AEAD (GCM o ChaCha20-Poly1305).
    # TLS 1.3 negocia sus propios ciphers (TLS_AES_128_GCM_SHA256 etc) automaticamente.
    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_tickets       off;
    ssl_session_timeout       1d;
    ssl_session_cache         shared:SSL:10m;

    # OCSP stapling: el server adjunta el estado de revocacion al handshake,
    # asi el browser no pregunta al CA por separado (performance + privacidad).
    # Requiere DNS para queries al responder (o.pki.goog para Google Trust).
    ssl_stapling              on;
    ssl_stapling_verify       on;
    ssl_trusted_certificate   ${ssl_cert};
    resolver                  1.1.1.1 8.8.8.8 valid=60s;
    resolver_timeout          5s;

    # Security headers (always = se aplican tambien a respuestas de error).
    # HSTS: forza HTTPS por 1 ano desde la primera visita.
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options              DENY                            always;
    add_header X-Content-Type-Options       nosniff                         always;
    add_header Referrer-Policy              "strict-origin-when-cross-origin" always;

    # CSP: SPA estatica, sin nonce por request (nginx no genera uno por
    # archivo). El unico <style> inline (loader inicial en index.html) se
    # permite por HASH exacto -- si se edita ese bloque hay que recalcular
    # el hash (ver comentario en frontend/index.html) y actualizarlo aqui.
    # connect-src/frame-src incluyen login.microsoftonline.com (MSAL, login
    # y posible iframe de renovacion silenciosa) y graph.microsoft.com (foto
    # de perfil). img-src incluye los tiles de OpenStreetMap (Leaflet).
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'sha256-g1QKmzaBQB8PYHILLpE3sccnhXgONiKzyUCs1r/BftM='; img-src 'self' data: blob: https://*.tile.openstreetmap.org; font-src 'self'; connect-src 'self' https://login.microsoftonline.com https://graph.microsoft.com; frame-src https://login.microsoftonline.com; frame-ancestors 'none'; base-uri 'self'; object-src 'none'; form-action 'self'" always;

    # Permissions-Policy: la app SI usa camara (captura biometrica facial) y
    # geolocalizacion (mapas/confirmacion de entrega) -- NO bloquearlas.
    # Microfono no se usa en ningun lado -- se bloquea.
    add_header Permissions-Policy "camera=(self), microphone=(), geolocation=(self)" always;

    # HTML/SPA: revalidar SIEMPRE. El index.html apunta a los JS hasheados;
    # si se cachea, el browser sigue cargando el bundle viejo tras un deploy.
    # 'no-cache' = puede guardar pero DEBE revalidar (nginx responde 304 si no cambio).
    add_header Cache-Control "no-cache" always;

    root /app/frontend/current;
    index index.html;

    # Assets con hash en el nombre (Vite): el contenido nunca cambia para un
    # mismo nombre -> cache largo e inmutable. (Este location con add_header
    # propio NO hereda los del server; por eso re-agregamos nosniff.)
    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        add_header X-Content-Type-Options nosniff always;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /hubs {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_cache off;
        proxy_read_timeout 3600s;
    }
}
HTTPSEOF
  else
    # HTTP plano: setup inicial sin cert configurado.
    # Sin HSTS — no tiene sentido sin TLS — pero si los headers genericos.
    cat <<HTTPEOF
server {
    listen 80;
    server_name ${SERVER_NAME_VALUE};
    server_tokens off;

    add_header X-Frame-Options              DENY                            always;
    add_header X-Content-Type-Options       nosniff                         always;
    add_header Referrer-Policy              "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'sha256-g1QKmzaBQB8PYHILLpE3sccnhXgONiKzyUCs1r/BftM='; img-src 'self' data: blob: https://*.tile.openstreetmap.org; font-src 'self'; connect-src 'self' https://login.microsoftonline.com https://graph.microsoft.com; frame-src https://login.microsoftonline.com; frame-ancestors 'none'; base-uri 'self'; object-src 'none'; form-action 'self'" always;
    add_header Permissions-Policy "camera=(self), microphone=(), geolocation=(self)" always;

    # HTML/SPA: revalidar SIEMPRE para tomar el bundle nuevo tras un deploy.
    add_header Cache-Control "no-cache" always;

    root /app/frontend/current;
    index index.html;

    # Assets con hash en el nombre (Vite): el contenido nunca cambia para un
    # mismo nombre -> cache largo e inmutable. (Este location con add_header
    # propio NO hereda los del server; por eso re-agregamos nosniff.)
    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        add_header X-Content-Type-Options nosniff always;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /hubs {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_cache off;
        proxy_read_timeout 3600s;
    }
}
HTTPEOF
  fi
}

# =============================================================================
# MAIN
# =============================================================================

require_root

# 1. Bootstrap dependencies from assets/
run_bootstrap

# 2. Enable nginx
log "Habilitando nginx..."
systemctl enable --now nginx
ok "nginx activo."

# 3. Service user (dedicado, no-root) — debe existir antes del chown de directorios.
create_service_user

# 4. Directory structure
log "Creando estructura /app/..."
mkdir -p "$DEPLOY_DIR" /app/releases /app/config /app/secrets /app/artifacts /app/artifacts/ssl
mkdir -p /app/deploy/storage/backups /app/deploy/storage/migrations/applied /app/deploy/storage/evidences
mkdir -p /etc/nginx/ssl

# /app/secrets: dueno app-backend, chmod 700 (solo el servicio entra).
chown "$SERVICE_USER:$SERVICE_GROUP" /app/secrets
chmod 700 /app/secrets

# /app/deploy/storage/evidences: dueno app-backend (el backend escribe aca).
chown -R "$SERVICE_USER:$SERVICE_GROUP" /app/deploy/storage/evidences

# Drop zone para certificados: el operador deja aca, configure-https los procesa.
chown root:root /app/artifacts/ssl
chmod 700 /app/artifacts/ssl

# Target final que usa nginx (master corre como root, lee de aca antes de fork).
chown root:root /etc/nginx/ssl
chmod 700 /etc/nginx/ssl

ok "Directorios creados (incluye drop zone /app/artifacts/ssl y target /etc/nginx/ssl)."

# 4. Centralized config (UNICA fuente de secretos)
setup_config

# 5. Nginx configuration (idempotente con drift detection)
resolve_server_name
log "Verificando configuracion de Nginx..."
nginx_expected="$(render_nginx_site_config)"
if apply_file_if_drifted /etc/nginx/sites-available/app "$nginx_expected" "Nginx site config"; then
  : # sin cambios — nada que hacer
else
  ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
  rm -f /etc/nginx/sites-enabled/default
  if nginx -t; then
    systemctl reload nginx
    ok "Nginx recargado."
  else
    err "nginx -t fallo. Revisa /etc/nginx/sites-available/app antes de reload."
    exit 1
  fi
fi

# 6. Backend systemd service (idempotente con drift detection)
log "Verificando backend.service..."
backend_unit_expected="$(render_backend_service_unit)"
if apply_file_if_drifted /etc/systemd/system/backend.service "$backend_unit_expected" "backend.service"; then
  : # sin cambios — nada que hacer
else
  systemctl daemon-reload
  systemctl enable backend
  warn "backend.service cambio. Para aplicar: systemctl restart backend"
fi

# 7. Registrar CLI global 'deploy'
log "Registrando CLI global 'deploy'..."
chmod +x "$DEPLOY_DIR/bin/deploy"
chmod +x "$DEPLOY_DIR/bin/menu.sh"
# Crear symlink en /usr/local/bin para que 'deploy' funcione desde cualquier lado
ln -sf "$DEPLOY_DIR/bin/deploy" /usr/local/bin/deploy
ok "CLI 'deploy' registrada en /usr/local/bin/deploy"

log "Servidor preparado."
log "  Menu de operaciones : deploy menu"
log "  CLI deploy           : deploy <modulo> <accion>"
log "  Instalar componente  : deploy backend install"

if config_has_placeholders; then
  echo
  warn "=================================================================="
  warn "  ATENCION: config.env tiene placeholders CHANGE_ME sin completar."
  warn "  El backend NO va a arrancar hasta que los reemplaces."
  warn ""
  warn "  Para completarlo:"
  warn "    nano $CONFIG_FILE"
  warn "    (o re-corre: deploy system setup)"
  warn ""
  warn "  Despues del cambio, reinicia el servicio:"
  warn "    systemctl restart backend"
  warn "=================================================================="
  echo
  info "Para verificar la conexion a la BD manualmente:"
  info "  MariaDB : mariadb -h <server> -P <port> -u <user> -p --ssl-verify-server-cert=0 -e \"SELECT 1\""
  echo
fi
