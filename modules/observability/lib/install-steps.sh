#!/usr/bin/env bash
# =============================================================================
# modules/observability/lib/install-steps.sh
#
# Install / upgrade orchestration for the observability stack (ADR-007).
# Entry point: obs_install [--upgrade] [--non-interactive] [--yes]
#              [--admin-user USER] [--admin-password PASS]
# =============================================================================

# ── Argument parsing shared by install.sh and upgrade.sh ──────────────────────
obs_parse_args() {
  OBS_UPGRADE=0
  OBS_NON_INTERACTIVE=0
  OBS_ASSUME_YES=0
  OBS_ADMIN_USER_OPT=""
  OBS_ADMIN_PASSWORD_OPT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --upgrade)         OBS_UPGRADE=1 ;;
      --non-interactive) OBS_NON_INTERACTIVE=1 ;;
      --yes|-y)          OBS_ASSUME_YES=1 ;;
      --admin-user)      OBS_ADMIN_USER_OPT="${2:-}"; shift ;;
      --admin-password)  OBS_ADMIN_PASSWORD_OPT="${2:-}"; shift ;;
      *) err "Opcion desconocida: $1"; return 1 ;;
    esac
    shift
  done
}

obs_resolve_server_name() {
  load_config || true
  OBS_SERVER_NAME="${NGINX_SERVER_NAME:-_}"
  [[ -z "$OBS_SERVER_NAME" ]] && OBS_SERVER_NAME="_"
  log "Dominio para root_url de Grafana: $OBS_SERVER_NAME"
}

# ── Artifacts: assets/observability first, official download otherwise ────────
obs_acquire_artifacts() {
  step "Adquisicion de binarios (assets offline o descarga oficial)"
  mkdir -p "$OBS_STAGE_DIR"

  local offline=0 online=0 c file asset stage url sha
  for c in "${OBS_COMPONENTS[@]}"; do
    file="$(obs_field "$c" FILE)"
    sha="$(obs_field "$c" SHA256)"
    url="$(obs_field "$c" URL)"
    asset="$OBS_ASSETS_DIR/$file"
    stage="$OBS_STAGE_DIR/$file"

    if [[ -f "$asset" ]]; then
      log "[$c] asset offline encontrado: $asset"
      cp -f "$asset" "$stage"
      offline=$((offline + 1))
    else
      log "[$c] sin asset offline; descargando desde la fuente oficial..."
      info "  $url"
      if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$stage" "$url"; then
        err "[$c] descarga fallida: $url"
        err "  Para el server air-gapped: ejecuta scripts/fetch-observability-assets.sh"
        err "  en una maquina con Internet y copia assets/observability/ al server."
        return 1
      fi
      online=$((online + 1))
    fi

    verify_artifact_sha256 "$stage" "$sha" "$c v$(obs_field "$c" VERSION)" || return 1
  done

  ok "Artefactos listos ($offline desde assets, $online descargados)."
}

# ── Users + directories ───────────────────────────────────────────────────────
obs_setup_users_dirs() {
  step "Usuarios de sistema y directorios"
  local u
  for u in "${OBS_USERS[@]}"; do
    ensure_service_user "$u"
  done

  install -d -m 0755 -o prometheus -g prometheus "$OBS_PROM_ETC" "$OBS_PROM_DATA"
  install -d -m 0755 -o loki -g loki "$OBS_LOKI_ETC" "$OBS_LOKI_DATA"
  install -d -m 0755 -o alloy -g alloy "$OBS_ALLOY_ETC" "$OBS_ALLOY_DATA"
  install -d -m 0755 -o grafana -g grafana "$OBS_GRAFANA_ETC" "$OBS_GRAFANA_DATA" "$OBS_GRAFANA_LOG"
  install -d -m 0755 -o grafana -g grafana \
    "$OBS_GRAFANA_ETC/provisioning" \
    "$OBS_GRAFANA_ETC/provisioning/datasources" \
    "$OBS_GRAFANA_ETC/provisioning/dashboards" \
    "$OBS_GRAFANA_ETC/provisioning/plugins" \
    "$OBS_GRAFANA_ETC/provisioning/alerting" \
    "$OBS_GRAFANA_ETC/provisioning/notifiers" \
    "$OBS_GRAFANA_ETC/dashboards"
  ok "Directorios de estado y configuracion listos."
}

# ── Binary installation ───────────────────────────────────────────────────────
# install_bin_from_archive <component> <binary-glob> <dest-name>
obs_install_bin() {
  local component="$1" glob="$2" dest="$3"
  local archive="$OBS_STAGE_DIR/$(obs_field "$component" FILE)"
  local kind tmp found
  kind="$(obs_field "$component" KIND)"
  tmp="$(mktemp -d)"

  if [[ "$kind" == "zip" ]]; then
    extract_zip "$archive" "$tmp" || { rm -rf "$tmp"; return 1; }
  else
    tar -xzf "$archive" -C "$tmp" || { rm -rf "$tmp"; return 1; }
  fi

  found="$(find "$tmp" -type f -name "$glob" ! -name '*.zip' ! -name '*.gz' | head -1)"
  if [[ -z "$found" ]]; then
    err "[$component] binario '$glob' no encontrado dentro de $archive"
    rm -rf "$tmp"
    return 1
  fi

  install -m 0755 -o root -g root "$found" "/usr/local/bin/$dest"
  rm -rf "$tmp"
  ok "[$component] instalado en /usr/local/bin/$dest ($(obs_field "$component" VERSION))."
}

obs_install_grafana_home() {
  local archive="$OBS_STAGE_DIR/$(obs_field grafana FILE)"
  local ver="$(obs_field grafana VERSION)"
  local dest="/usr/share/grafana-${ver}"
  local tmp top
  tmp="$(mktemp -d)"
  tar -xzf "$archive" -C "$tmp" || { rm -rf "$tmp"; return 1; }

  # El tarball oficial trae un unico directorio raiz grafana-<ver>/.
  top="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
  if [[ -z "$top" ]]; then
    err "[grafana] estructura inesperada en el tarball."
    rm -rf "$tmp"
    return 1
  fi

  if [[ -d "$dest" ]]; then
    # Ya instalada esa version: refrescar (install -m preserva permisos).
    cp -aT "$top" "$dest"
  else
    mv "$top" "$dest"
  fi
  rm -rf "$tmp"

  ln -sfn "$dest" "$OBS_GRAFANA_HOME"
  printf '#!/usr/bin/env sh\nexec %s/bin/grafana "$@"\n' "$OBS_GRAFANA_HOME" > /usr/local/bin/grafana
  chmod 0755 /usr/local/bin/grafana
  ok "[grafana] home instalada en $dest (symlink $OBS_GRAFANA_HOME)."
}

obs_install_binaries() {
  step "Instalacion de binarios"
  obs_install_bin prometheus prometheus prometheus
  obs_install_bin loki 'loki-linux-amd64' loki
  obs_install_bin alloy 'alloy-linux-amd64' alloy
  obs_install_grafana_home
}

# ── Config + units ────────────────────────────────────────────────────────────
obs_write_configs() {
  step "Configuracion de componentes"
  apply_config_file "$OBS_PROM_ETC/prometheus.yml" "$(obs_render_prometheus_yml)" "prometheus.yml" || true
  apply_config_file "$OBS_LOKI_ETC/config.yml" "$(obs_render_loki_yml)" "loki config.yml" || true
  apply_config_file "$OBS_ALLOY_ETC/config.alloy" "$(obs_render_alloy_config)" "alloy config.alloy" || true
  apply_config_file "$OBS_GRAFANA_ETC/grafana.ini" "$(obs_render_grafana_ini)" "grafana.ini" || true
  apply_config_file "$OBS_GRAFANA_ETC/provisioning/datasources/datasources.yml" \
    "$(obs_render_grafana_datasources)" "grafana datasources" || true
  apply_config_file "$OBS_GRAFANA_ETC/provisioning/dashboards/provider.yml" \
    "$(obs_render_grafana_dashboard_provider)" "grafana dashboard provider" || true
  apply_config_file "$OBS_GRAFANA_ETC/dashboards/biometric-api.json" \
    "$(obs_render_grafana_dashboard)" "biometric-api dashboard" || true
}

obs_setup_grafana_creds() {
  step "Credenciales de administrador de Grafana"
  if [[ -f "$OBS_GRAFANA_ENV" ]] && grep -q '^GF_SECURITY_ADMIN_PASSWORD=' "$OBS_GRAFANA_ENV" 2>/dev/null; then
    OBS_ADMIN_USER="$(grep '^GF_SECURITY_ADMIN_USER=' "$OBS_GRAFANA_ENV" | cut -d= -f2-)"
    OBS_ADMIN_PASSWORD="$(grep '^GF_SECURITY_ADMIN_PASSWORD=' "$OBS_GRAFANA_ENV" | cut -d= -f2-)"
    ok "Credenciales existentes reutilizadas (usuario: $OBS_ADMIN_USER)."
    return 0
  fi

  OBS_ADMIN_USER="${OBS_ADMIN_USER_OPT:-}"
  if [[ -z "$OBS_ADMIN_USER" && "$OBS_NON_INTERACTIVE" != "1" ]]; then
    read -rp "Usuario administrador de Grafana [$OBS_GRAFANA_ADMIN_DEFAULT]: " OBS_ADMIN_USER || true
  fi
  [[ -z "$OBS_ADMIN_USER" ]] && OBS_ADMIN_USER="$OBS_GRAFANA_ADMIN_DEFAULT"

  local generated=0
  OBS_ADMIN_PASSWORD="${OBS_ADMIN_PASSWORD_OPT:-}"
  if [[ -z "$OBS_ADMIN_PASSWORD" && "$OBS_NON_INTERACTIVE" != "1" ]]; then
    read -rsp "Password de administrador (Enter = autogenerar): " OBS_ADMIN_PASSWORD || true
    echo
  fi
  if [[ -z "$OBS_ADMIN_PASSWORD" ]]; then
    if ! command -v openssl >/dev/null 2>&1; then
      err "openssl no disponible para autogenerar el password; pasalo con --admin-password."
      return 1
    fi
    OBS_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
    generated=1
  fi

  mkdir -p "$(dirname "$OBS_GRAFANA_ENV")"
  printf '%s\n' "$(obs_render_grafana_env)" > "$OBS_GRAFANA_ENV"
  chown root:root "$OBS_GRAFANA_ENV"
  chmod 600 "$OBS_GRAFANA_ENV"
  ok "Credenciales guardadas en $OBS_GRAFANA_ENV (600 root:root)."

  echo
  warn "=============================================================="
  warn "  Grafana admin"
  warn "    usuario    : $OBS_ADMIN_USER"
  warn "    password   : $OBS_ADMIN_PASSWORD"
  if [[ "$generated" == "1" ]]; then
    warn "  (password AUTOGENERADO; guardalo ahora, no se vuelve a mostrar)"
  fi
  warn "  Cambialo desde la UI cuando quieras; persiste en $OBS_GRAFANA_ENV."
  warn "=============================================================="
  echo
}

obs_write_units() {
  step "Unidades systemd"
  local changed=0
  apply_config_file "$OBS_SYSTEMD_DIR/prometheus.service" "$(obs_render_prometheus_service)" "prometheus.service" || changed=1
  apply_config_file "$OBS_SYSTEMD_DIR/loki.service" "$(obs_render_loki_service)" "loki.service" || changed=1
  apply_config_file "$OBS_SYSTEMD_DIR/alloy.service" "$(obs_render_alloy_service)" "alloy.service" || changed=1
  apply_config_file "$OBS_SYSTEMD_DIR/grafana-server.service" "$(obs_render_grafana_service)" "grafana-server.service" || changed=1
  systemctl daemon-reload
  [[ "$changed" == "1" ]] && ok "Unidades escritas/actualizadas." || ok "Unidades ya sincronizadas."
}

obs_start_services() {
  step "Arranque/recarga de servicios"
  local u
  for u in "${OBS_UNITS[@]}"; do
    systemctl enable "$u" >/dev/null 2>&1 || true
    # restart (no solo start) para que install/upgrade aplique cambios de config.
    systemctl restart "$u"
    if systemctl is-active --quiet "$u"; then
      ok "$u activo."
    else
      err "$u NO arranco. Revisa: journalctl -u $u -n 50 --no-pager"
    fi
  done
}

# ── nginx integration ─────────────────────────────────────────────────────────
obs_setup_nginx() {
  step "Integracion con nginx (/obs y /collect)"
  if ! command -v nginx >/dev/null 2>&1; then
    warn "nginx no esta instalado; se omite la publicacion web."
    return 0
  fi

  apply_config_file "$OBS_NGINX_SNIPPET" "$(obs_render_nginx_snippet)" "nginx observability snippet" || true

  if [[ ! -f "$OBS_NGINX_SITE" ]]; then
    warn "No existe $OBS_NGINX_SITE todavia."
    warn "Al correr 'deploy system setup' el sitio incluira el snippet automaticamente."
    return 0
  fi

  if ! grep -q 'snippets/observability.conf' "$OBS_NGINX_SITE"; then
    local backup="${OBS_NGINX_SITE}.bak.$(date '+%Y%m%d-%H%M%S')"
    cp -p "$OBS_NGINX_SITE" "$backup"
    awk '
      /^[[:space:]]*server_name[[:space:]]/ {
        print
        print "    include /etc/nginx/snippets/observability.conf;"
        next
      }
      { print }
    ' "$OBS_NGINX_SITE" > "${OBS_NGINX_SITE}.tmp" && mv "${OBS_NGINX_SITE}.tmp" "$OBS_NGINX_SITE"
    warn "include agregado a $OBS_NGINX_SITE (backup en $backup)."
  else
    ok "El sitio ya incluye el snippet de observabilidad."
  fi

  obs_nginx_reload || return 1
}

# ── Main ──────────────────────────────────────────────────────────────────────
obs_install() {
  require_root
  obs_parse_args "$@" || exit 1
  obs_resolve_server_name

  echo
  divider
  if [[ "$OBS_UPGRADE" == "1" ]]; then
    echo "  OBSERVABILITY — UPGRADE"
  else
    echo "  OBSERVABILITY — INSTALL"
  fi
  divider
  info "Grafana $(obs_field grafana VERSION) · Prometheus $(obs_field prometheus VERSION) · Loki $(obs_field loki VERSION) · Alloy $(obs_field alloy VERSION)"

  if [[ "$OBS_ASSUME_YES" != "1" && "$OBS_NON_INTERACTIVE" != "1" ]]; then
    confirm "Continuar con la instalacion?" || { log "Cancelado."; return 0; }
  fi

  obs_acquire_artifacts      || exit 1
  obs_setup_users_dirs
  obs_install_binaries       || exit 1
  obs_write_configs
  obs_setup_grafana_creds    || exit 1
  obs_write_units
  obs_start_services
  obs_setup_nginx            || warn "nginx no recargado; revisa la salida de nginx -t."

  echo
  divider
  ok "Observabilidad instalada."
  local host="$OBS_SERVER_NAME"; [[ "$host" == "_" ]] && host="<dominio>"
  log "  Panel Grafana : https://${host}/obs"
  log "  Faro collect  : https://${host}/collect"
  log "  Internos      : Prometheus 9090 · Loki 3100 · Alloy OTLP 4317/4318 · Faro 12347 (loopback)"
  log "  Estado        : deploy observability status"
  divider
}
