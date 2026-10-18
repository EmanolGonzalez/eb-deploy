#!/usr/bin/env bash
# =============================================================================
# modules/observability/lib/render.sh
#
# Renderers for every configuration artifact the observability stack needs.
# Namespaced (obs_render_*) so they never collide with setup-server.sh's
# render_* functions when both are sourced in the same process.
#
# Variables read from the caller's scope: OBS_SERVER_NAME, OBS_RETENTION_PROM,
# OBS_RETENTION_LOKI, OBS_ADMIN_USER, OBS_VERSION_*.
# =============================================================================

# ── Prometheus ────────────────────────────────────────────────────────────────

obs_render_prometheus_yml() {
  cat <<EOF
# /etc/prometheus/prometheus.yml — gestionado por 'deploy observability install'.
# No editar a mano: vuelve a su forma canonica en el proximo install/upgrade.
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    host: "${OBS_SERVER_NAME}"

scrape_configs:
  # Prometheus scrapea su propio endpoint (sano = target UP).
  - job_name: prometheus
    static_configs:
      - targets: ["127.0.0.1:9090"]

  # Metricas propias de Alloy (WAL de remote_write, receivers, scrapes).
  - job_name: alloy
    static_configs:
      - targets: ["127.0.0.1:12345"]

  # Contrato API (ADR-007): GET /metrics en formato Prometheus.
  - job_name: biometric-api
    metrics_path: /metrics
    static_configs:
      - targets: ["127.0.0.1:5000"]
EOF
}

obs_render_prometheus_service() {
  cat <<EOF
[Unit]
Description=Prometheus (observabilidad biometrica, ADR-007)
Documentation=https://prometheus.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=${OBS_PROM_ETC}/prometheus.yml \\
  --storage.tsdb.path=${OBS_PROM_DATA} \\
  --storage.tsdb.retention.time=${OBS_RETENTION_PROM} \\
  --web.listen-address=127.0.0.1:9090 \\
  --web.enable-lifecycle \\
  --web.enable-remote-write-receiver

# remote_write-receiver: Alloy empuja aca las metricas OTLP y las del scrape.
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${OBS_PROM_DATA}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# ── Loki ──────────────────────────────────────────────────────────────────────

obs_render_loki_yml() {
  cat <<EOF
# /etc/loki/config.yml — gestionado por 'deploy observability install'.
# Binario unico (target all), almacenamiento en filesystem, retencion 30d.
# Ingesta OTLP nativa habilitada en /otlp/v1/logs (logs de la API via Alloy).
auth_enabled: false

server:
  http_listen_address: 127.0.0.1
  http_listen_port: 3100
  grpc_listen_address: 127.0.0.1
  grpc_listen_port: 9096
  log_level: info

# El querier debe hablar con el query frontend por loopback. Sin esta linea
# Loki anuncia el frontend con la IP del host (p. ej. 10.0.0.4) y las queries
# fallan con "connection refused" aunque las escrituras (push) funcionen.
frontend_worker:
  frontend_address: 127.0.0.1:9096

common:
  path_prefix: ${OBS_LOKI_DATA}
  storage:
    filesystem:
      chunks_directory: ${OBS_LOKI_DATA}/chunks
      rules_directory: ${OBS_LOKI_DATA}/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: ${OBS_RETENTION_LOKI}
  allow_structured_metadata: true
  reject_old_samples: true
  reject_old_samples_max_age: 168h

compactor:
  working_directory: ${OBS_LOKI_DATA}/compactor
  retention_enabled: true
  delete_request_store: filesystem

ruler:
  storage:
    type: local
    local:
      directory: ${OBS_LOKI_DATA}/rules
EOF
}

obs_render_loki_service() {
  cat <<EOF
[Unit]
Description=Loki (agregacion de logs, ADR-007)
Documentation=https://grafana.com/docs/loki/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=${OBS_LOKI_ETC}/config.yml
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${OBS_LOKI_DATA}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# ── Grafana Alloy ─────────────────────────────────────────────────────────────

obs_render_alloy_config() {
  cat <<EOF
// /etc/alloy/config.alloy — gestionado por 'deploy observability install'.
// Unico receptor de telemetria (loopback): OTLP 4317/4318 y Faro /collect.
// Reenvia metricas a Prometheus (remote_write) y logs a Loki.
logging {
  level  = "info"
  format = "logfmt"
}

// --- OTLP receiver (API .NET -> Alloy) ---
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "127.0.0.1:4317"
  }
  http {
    endpoint = "127.0.0.1:4318"
  }
  output {
    metrics = [otelcol.exporter.prometheus.default.input]
    logs    = [otelcol.exporter.loki.default.input]
  }
}

otelcol.exporter.prometheus "default" {
  forward_to = [prometheus.remote_write.default.receiver]
}

otelcol.exporter.loki "default" {
  forward_to = [loki.write.default.receiver]
}

// --- Destinos ---
prometheus.remote_write "default" {
  endpoint {
    url = "http://127.0.0.1:9090/api/v1/write"
  }
}

loki.write "default" {
  endpoint {
    url = "http://127.0.0.1:3100/loki/api/v1/push"
  }
}

// --- Scrape del contrato API /metrics -> Prometheus ---
prometheus.scrape "biometric_api" {
  targets         = [{"__address__" = "127.0.0.1:5000"}]
  metrics_path    = "/metrics"
  scrape_interval = "15s"
  forward_to      = [prometheus.remote_write.default.receiver]
}

// --- Faro Web SDK (frontend) -> POST /collect (publicado por nginx) ---
// Session replay desactivado por contrato (regla PII, ADR-007): no se
// provisiona almacenamiento de replay ni se exponen rutas para el.
faro.receiver "default" {
  server {
    listen_address = "127.0.0.1"
    listen_port    = 12347
  }
  output {
    logs   = [loki.write.default.receiver]
    traces = []
  }
}
EOF
}

obs_render_alloy_service() {
  cat <<EOF
[Unit]
Description=Grafana Alloy (receptor OTLP/Faro, ADR-007)
Documentation=https://grafana.com/docs/alloy/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=alloy
Group=alloy
ExecStart=/usr/local/bin/alloy run \\
  --server.http.listen-addr=127.0.0.1:12345 \\
  --storage.path=${OBS_ALLOY_DATA} \\
  ${OBS_ALLOY_ETC}/config.alloy
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${OBS_ALLOY_DATA}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# ── Grafana ───────────────────────────────────────────────────────────────────

obs_render_grafana_ini() {
  local root_url
  if [[ -n "$OBS_SERVER_NAME" && "$OBS_SERVER_NAME" != "_" ]]; then
    root_url="https://${OBS_SERVER_NAME}/obs"
  else
    root_url="http://localhost:3000/obs"
  fi
  cat <<EOF
# /etc/grafana/grafana.ini — gestionado por 'deploy observability install'.
# Subruta /obs publicada por nginx (ADR-007).
[server]
protocol = http
http_addr = 127.0.0.1
http_port = 3000
domain = ${OBS_SERVER_NAME}
root_url = ${root_url}
serve_from_sub_path = true
enforce_domain = false

[security]
# admin_user / admin_password se inyectan por EnvironmentFile (${OBS_GRAFANA_ENV}).
disable_gravatar = true
cookie_secure = true
allow_embedding = false

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[paths]
data = ${OBS_GRAFANA_DATA}
logs = ${OBS_GRAFANA_LOG}
provisioning = ${OBS_GRAFANA_ETC}/provisioning
plugins = ${OBS_GRAFANA_DATA}/plugins

[database]
type = sqlite3
path = ${OBS_GRAFANA_DATA}/grafana.db

[analytics]
reporting_enabled = false
check_for_updates = false
check_for_plugin_updates = false

# ADR-007: server air-gapped. No descargar/actualizar plugins desde Internet.
[plugins]
preinstall_disabled = true
preinstall_auto_update = false

[log]
mode = console file
level = info
EOF
}

obs_render_grafana_service() {
  cat <<EOF
[Unit]
Description=Grafana (panel de observabilidad, ADR-007)
Documentation=https://grafana.com/docs/grafana/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=grafana
Group=grafana
# Credenciales de administrador (600 root) — convencion de secretos del repo.
EnvironmentFile=${OBS_GRAFANA_ENV}
# Usuario sin home: Grafana necesita un HOME escribible para su cache.
Environment=HOME=${OBS_GRAFANA_DATA}
Environment=GF_PATHS_DATA=${OBS_GRAFANA_DATA}
Environment=GF_PATHS_LOGS=${OBS_GRAFANA_LOG}
ExecStart=${OBS_GRAFANA_HOME}/bin/grafana server \\
  --homepath=${OBS_GRAFANA_HOME} \\
  --config=${OBS_GRAFANA_ETC}/grafana.ini
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${OBS_GRAFANA_DATA} ${OBS_GRAFANA_LOG} ${OBS_GRAFANA_ETC}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

obs_render_grafana_env() {
  cat <<EOF
# ${OBS_GRAFANA_ENV} — credenciales del administrador de Grafana.
# chmod 600 root:root. Editado por 'deploy observability install'.
# Formato EnvironmentFile de systemd (sin export, sin comillas).
GF_SECURITY_ADMIN_USER=${OBS_ADMIN_USER}
GF_SECURITY_ADMIN_PASSWORD=${OBS_ADMIN_PASSWORD}
EOF
}

obs_render_grafana_datasources() {
  cat <<EOF
# /etc/grafana/provisioning/datasources/datasources.yml
# Datasources provisionados (ADR-007): Prometheus + Loki.
# uid FIJO y explicito: el dashboard provisionado referencia los datasources
# por uid ("prometheus"/"loki"); sin uid Grafana asigna uno aleatorio y los
# paneles fallan con "Datasource prometheus was not found".
# Nota: Grafana aplica el uid en el primer provisioning (instalacion limpia).
# Si se actualiza una instalacion previa con uids auto-generados, hay que
# eliminar la fila vieja (editable:false no permite DELETE por API): con
# grafana detenido, borrar todas las filas de data_source en grafana.db y reinstalar.
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: false
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://127.0.0.1:3100
    editable: false
EOF
}

obs_render_grafana_dashboard_provider() {
  cat <<EOF
# /etc/grafana/provisioning/dashboards/provider.yml
apiVersion: 1
providers:
  - name: biometric
    orgId: 1
    folder: Biometric
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
EOF
}

# Starter dashboard: API request rate / latency / errors + targets up.
obs_render_grafana_dashboard() {
  cat <<'EOF'
{
  "annotations": { "list": [] },
  "editable": true,
  "graphTooltip": 1,
  "panels": [
    {
      "id": 1,
      "title": "API request rate (req/s)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [
        { "refId": "A", "expr": "sum(rate(http_server_request_duration_seconds_count{job=\"biometric-api\"}[5m]))" }
      ]
    },
    {
      "id": 2,
      "title": "API latency p95 (s)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [
        { "refId": "A", "expr": "histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{job=\"biometric-api\"}[5m])))" }
      ]
    },
    {
      "id": 3,
      "title": "API errors 5xx (req/s)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [
        { "refId": "A", "expr": "sum(rate(http_server_request_duration_seconds_count{job=\"biometric-api\",http_response_status_code=~\"5..\"}[5m]))" }
      ]
    },
    {
      "id": 4,
      "title": "Targets up",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [
        { "refId": "A", "expr": "up" }
      ]
    }
  ],
  "refresh": "30s",
  "schemaVersion": 39,
  "tags": ["biometric", "adr-007"],
  "time": { "from": "now-1h", "to": "now" },
  "timezone": "browser",
  "title": "Entrega Biometrica — API Overview",
  "uid": "biometric-api-overview",
  "version": 1
}
EOF
}

# ── nginx ─────────────────────────────────────────────────────────────────────

obs_render_nginx_snippet() {
  cat <<'EOF'
# /etc/nginx/snippets/observability.conf — gestionado por
# 'deploy observability install'. Solo dos rutas salen a Internet:
#   /obs/    -> Grafana (subruta, autenticacion propia)
#   /collect -> Grafana Alloy Faro receiver (POST del navegador)
# El resto de puertos (9090/3100/4317/4318/12347) queda en loopback.
# El map $connection_upgrade proviene del server block del sitio.

location = /obs {
    return 301 /obs/;
}

location /obs/ {
    # Grafana necesita scripts/estilos inline y eval: CSP propia para esta ruta
    # (la CSP del SPA se define a nivel de server y se heredaria, bloqueando a Grafana).
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'self'; object-src 'none'" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    # Grafana Live (websockets) para refresco de paneles.
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 3600s;
}

# /collect es un receptor Faro POST-only: responde JSON y no ejecuta recursos
# (no sirve HTML ni scripts), asi que la CSP heredada del server no lo afecta.
# No se define CSP propia aqui para no abrir la superficie innecesariamente.
location /collect {
    proxy_pass http://127.0.0.1:12347;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
EOF
}
