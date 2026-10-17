#!/usr/bin/env bash
# =============================================================================
# modules/health/lib/simple.sh
#
# One-touch, plain-language system status for the operator. No JSON, no
# engineering jargon. It reuses the probes the technical commands already run:
#   - systemd states (nginx / backend, and the observability units)
#   - the nginx frontend probe (HTTP 200 on http://localhost/)
#   - the backend /api/health payload ("sql_server" check -> Base de datos)
#
# Each component is a small overridable probe so the suite can pin both the OK
# and the FALLA output offline. Colors are emitted ONLY when stdout is a TTY.
# Exit code: 0 when everything is OK, 1 when anything fails.
# =============================================================================

# ── Per-component probes (overridable in tests) ───────────────────────────────

# Página web: nginx is running and the public site answers 200.
_hs_web_ok() {
  systemctl is-active --quiet nginx 2>/dev/null || return 1
  curl -fsS --max-time 5 "http://localhost/" >/dev/null 2>&1
}

# Aplicación: backend service is active and its health endpoint responds.
_hs_app_ok() {
  systemctl is-active --quiet backend 2>/dev/null || return 1
  [[ -n "$(_hs_health_payload)" ]]
}

# Raw /api/health body (empty when unreachable). Tries the configured endpoint
# first, then the known local defaults. No direct DB client dependency.
_hs_health_payload() {
  local url payload
  local candidates=()
  [[ -n "${BACKEND_HEALTH_ENDPOINT:-}" ]] && candidates+=("$BACKEND_HEALTH_ENDPOINT")
  candidates+=(
    "http://localhost:5000/api/health"
    "http://localhost/api/health"
    "http://localhost/health"
    "http://localhost/healthz"
  )
  for url in "${candidates[@]}"; do
    payload="$(curl -s --max-time 5 "$url" 2>/dev/null || true)"
    if [[ -n "$payload" ]]; then
      printf '%s' "$payload"
      return 0
    fi
  done
  return 1
}

# Base de datos: status of the "sql_server" check inside the /api/health payload.
# Prints Healthy/Degraded/Unhealthy, or nothing when it cannot be derived.
_hs_db_status() {
  local payload
  payload="$(_hs_health_payload)" || return 0
  printf '%s' "$payload" | tr '\n' ' ' \
    | grep -oE '"name"[[:space:]]*:[[:space:]]*"sql_server"[^}]*"status"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -1 \
    | sed -E 's/.*"([^"]+)"$/\1/' || true
}

# Observabilidad: only relevant when the stack is installed on this host.
_hs_obs_installed() {
  [[ -x /usr/local/bin/prometheus || -x /usr/local/bin/grafana \
     || -f /etc/systemd/system/prometheus.service \
     || -f /etc/systemd/system/grafana-server.service ]]
}

_hs_obs_ok() {
  local u
  for u in prometheus.service loki.service alloy.service grafana-server.service; do
    systemctl is-active --quiet "$u" 2>/dev/null || return 1
  done
}

# ── Rendering ─────────────────────────────────────────────────────────────────

_hs_render_line() { # <color> <reset> <tag> <label>
  local color="$1" reset="$2" tag="$3" label="$4" gap
  [[ "$tag" == "OK" ]] && gap="   " || gap=" "
  printf '%s[%s]%s%s%s\n' "$color" "$tag" "$reset" "$gap" "$label"
}

health_simple() {
  local use_color=false
  [[ -t 1 ]] && use_color=true
  local c_ok="" c_fail="" c_head="" c_reset=""
  if [[ "$use_color" == true ]]; then
    c_ok=$'\033[1;32m'; c_fail=$'\033[1;31m'; c_head=$'\033[1;37m'; c_reset=$'\033[0m'
  fi

  local failed=0
  local db_status

  echo "${c_head}ESTADO DEL SISTEMA${c_reset}"

  if _hs_web_ok; then
    _hs_render_line "$c_ok" "$c_reset" OK "Página web"
  else
    _hs_render_line "$c_fail" "$c_reset" FALLA "Página web"
    failed=1
  fi

  if _hs_app_ok; then
    _hs_render_line "$c_ok" "$c_reset" OK "Aplicación"
  else
    _hs_render_line "$c_fail" "$c_reset" FALLA "Aplicación"
    failed=1
  fi

  db_status="$(_hs_db_status)"
  if [[ "$db_status" == "Healthy" ]]; then
    _hs_render_line "$c_ok" "$c_reset" OK "Base de datos"
  else
    _hs_render_line "$c_fail" "$c_reset" FALLA "Base de datos"
    failed=1
  fi

  if _hs_obs_installed; then
    if _hs_obs_ok; then
      _hs_render_line "$c_ok" "$c_reset" OK "Observabilidad"
    else
      _hs_render_line "$c_fail" "$c_reset" FALLA "Observabilidad"
      failed=1
    fi
  fi

  echo
  if [[ "$failed" -eq 0 ]]; then
    printf '%s→ TODO FUNCIONANDO%s\n' "$c_ok" "$c_reset"
    return 0
  fi

  # One actionable, non-technical line per failing component.
  _hs_web_ok || printf '%s→ QUÉ HACER: Avisá al proveedor: la página web no responde.%s\n' "$c_fail" "$c_reset"
  _hs_app_ok || printf '%s→ QUÉ HACER: Avisá al proveedor: la aplicación no responde.%s\n' "$c_fail" "$c_reset"
  [[ "$db_status" == "Healthy" ]] || printf '%s→ QUÉ HACER: Avisá al proveedor: no hay conexión con la base de datos.%s\n' "$c_fail" "$c_reset"
  if _hs_obs_installed && ! _hs_obs_ok; then
    printf '%s→ QUÉ HACER: El monitoreo no responde. No afecta la operación; avisá al proveedor.%s\n' "$c_fail" "$c_reset"
  fi
  return 1
}
