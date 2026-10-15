#!/usr/bin/env bash
# =============================================================================
# modules/observability/lib/observability-common.sh
#
# Shared constants and helpers for the observability module (ADR-007):
# Grafana + Prometheus + Loki + Grafana Alloy as NATIVE systemd services
# (host-direct, no containers), installed offline from assets/observability/
# when present, or fetched from the official sources online otherwise.
#
# Layout on the target host (all binds are loopback only; only Grafana and
# the Alloy Faro collector are published through nginx, under /obs and
# /collect respectively):
#   Prometheus  -> 127.0.0.1:9090     config /etc/prometheus/prometheus.yml
#   Loki        -> 127.0.0.1:3100     config /etc/loki/config.yml
#   Alloy       -> OTLP 127.0.0.1:4317 (gRPC) / 4318 (HTTP)
#                  Faro 127.0.0.1:12347 (/collect)
#                  own UI/metrics 127.0.0.1:12345   config /etc/alloy/config.alloy
#   Grafana     -> 127.0.0.1:3000 (subpath /obs)       config /etc/grafana
# =============================================================================

OBS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBS_MODULE_DIR="$(cd "$OBS_LIB_DIR/.." && pwd)"
OBS_BASE="$(cd "$OBS_MODULE_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$OBS_BASE/core/logger.sh"
# shellcheck source=/dev/null
source "$OBS_BASE/core/input.sh"
# shellcheck source=/dev/null
source "$OBS_BASE/core/config.sh"
# shellcheck source=/dev/null
source "$OBS_BASE/core/system.sh"

# ── Pinned versions (ADR-007, verified against the official channels) ─────────
# The authoritative record also lives in modules/observability/manifest.json and
# is mirrored in assets/manifest.json. Keep the three in sync.
OBS_RETENTION_PROM="15d"     # Prometheus retention (ADR-007: 15d revisable)
OBS_RETENTION_LOKI="720h"    # Loki retention (ADR-007: 30d revisable)

OBS_COMPONENTS=(grafana prometheus loki alloy)

# version | archive file | kind | sha256 | download url
OBS_VERSION_grafana="13.2.4"
OBS_FILE_grafana="grafana-13.2.4.linux-amd64.tar.gz"
OBS_KIND_grafana="tar.gz"
OBS_SHA256_grafana="c48765988fd88572607e4ea670251af8a8e64ab3e360d0f3cf67a6f3587b92ab"
OBS_URL_grafana="https://dl.grafana.com/oss/release/grafana-13.2.4.linux-amd64.tar.gz"

OBS_VERSION_prometheus="3.15.0"
OBS_FILE_prometheus="prometheus-3.15.0.linux-amd64.tar.gz"
OBS_KIND_prometheus="tar.gz"
OBS_SHA256_prometheus="2a542df32eac02ee17b9d844fb2aa1de00dafa5476579ba8a3ba862e9d572ea0"
OBS_URL_prometheus="https://github.com/prometheus/prometheus/releases/download/v3.15.0/prometheus-3.15.0.linux-amd64.tar.gz"

OBS_VERSION_loki="3.7.8"
OBS_FILE_loki="loki-linux-amd64.zip"
OBS_KIND_loki="zip"
OBS_SHA256_loki="62aea42c9cba52cd1642b3666ab37019a0ce4c24ab50b07e85dccc8d812f7d61"
OBS_URL_loki="https://github.com/grafana/loki/releases/download/v3.7.8/loki-linux-amd64.zip"

OBS_VERSION_alloy="1.20.1"
OBS_FILE_alloy="alloy-linux-amd64.zip"
OBS_KIND_alloy="zip"
OBS_SHA256_alloy="451fe650e8277d22d69cb8db50bba809f581fe78decba7fce4027ef185457be9"
OBS_URL_alloy="https://github.com/grafana/alloy/releases/download/v1.20.1/alloy-linux-amd64.zip"

# ── Filesystem layout ─────────────────────────────────────────────────────────
OBS_ASSETS_DIR="$OBS_BASE/assets/observability"
OBS_STAGE_DIR="/app/artifacts/observability"

OBS_ETC_DIR="/etc"
OBS_SYSTEMD_DIR="/etc/systemd/system"
OBS_NGINX_SNIPPET="/etc/nginx/snippets/observability.conf"
OBS_NGINX_SITE="/etc/nginx/sites-available/app"

OBS_PROM_ETC="/etc/prometheus"
OBS_PROM_DATA="/var/lib/prometheus"
OBS_LOKI_ETC="/etc/loki"
OBS_LOKI_DATA="/var/lib/loki"
OBS_ALLOY_ETC="/etc/alloy"
OBS_ALLOY_DATA="/var/lib/alloy"
OBS_GRAFANA_ETC="/etc/grafana"
OBS_GRAFANA_HOME="/usr/share/grafana"
OBS_GRAFANA_DATA="/var/lib/grafana"
OBS_GRAFANA_LOG="/var/log/grafana"
OBS_GRAFANA_ENV="/etc/grafana/grafana.env"
OBS_GRAFANA_ADMIN_DEFAULT="admin"

OBS_UNITS=(prometheus.service loki.service alloy.service grafana-server.service)
OBS_USERS=(prometheus loki alloy grafana)

# ── Version lookups (indirect expansion on the per-component arrays above) ────
obs_field() { # obs_field <component> <field: VERSION|FILE|KIND|SHA256|URL>
  local component="$1" field="$2" var="OBS_${2}_${1}"
  printf '%s' "${!var:-}"
}

# ── Small helpers ─────────────────────────────────────────────────────────────
obs_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Comando requerido no disponible: $cmd"
    return 1
  fi
}

# apply_config_file <target> <content> <label>
#   Idempotent write with a timestamped backup when the content drifts.
#   Returns 1 when it changed the file, 0 when already in sync (like the
#   setup-server.sh drift helper).
apply_config_file() {
  local target="$1" content="$2" label="${3:-$target}"
  local dir
  dir="$(dirname "$target")"
  mkdir -p "$dir"

  if [[ ! -f "$target" ]]; then
    printf '%s\n' "$content" > "$target"
    ok "$label creado."
    return 1
  fi

  if diff -q <(printf '%s\n' "$content") "$target" >/dev/null 2>&1; then
    ok "$label sincronizado (sin cambios)."
    return 0
  fi

  local backup="${target}.bak.$(date '+%Y%m%d-%H%M%S')"
  cp -p "$target" "$backup"
  warn "$label difiere — backup en $backup"
  printf '%s\n' "$content" > "$target"
  ok "$label actualizado."
  return 1
}

# sha256_of <file> — prints the hex digest.
sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

# verify_artifact_sha256 <file> <expected> <label>
verify_artifact_sha256() {
  local file="$1" expected="$2" label="$3"
  if [[ -z "$expected" ]]; then
    warn "$label: sin checksum esperado; se omite la verificacion."
    return 0
  fi
  local actual
  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    err "Checksum invalido para $label"
    err "  Esperado: $expected"
    err "  Obtenido: $actual"
    return 1
  fi
  ok "$label: checksum verificado ($actual)."
}

# extract_zip <archive> <dest> — unzip if available, else python3's zipfile.
extract_zip() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$archive" -d "$dest"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "$archive" "$dest"
  else
    err "No hay 'unzip' ni 'python3' para extraer $archive."
    err "Instala unzip (assets/system) o agrega el binario ya extraido al asset."
    return 1
  fi
}

# ensure_service_user <name> — system user/group, no home, nologin.
ensure_service_user() {
  local name="$1"
  if id "$name" >/dev/null 2>&1; then
    return 0
  fi
  log "Creando usuario de sistema $name..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$name"
}

# obs_nginx_reload — nginx -t gate, then reload; never reload on a failed test.
obs_nginx_reload() {
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx
    ok "Nginx recargado."
    return 0
  fi
  err "nginx -t fallo; NO se recarga nginx. Revisa la configuracion."
  nginx -t || true
  return 1
}
