#!/usr/bin/env bash
# =============================================================================
# modules/observability/lib/status.sh
#
# Read-only status report for the observability stack (ADR-007).
# =============================================================================

obs_curl_code() { # [curl args...] url -> http code (or "----" when unreachable)
  local code
  code="$(curl -s -k -o /dev/null -w '%{http_code}' --max-time 5 "$@" 2>/dev/null || true)"
  [[ -z "$code" || "$code" == "000" ]] && code="----"
  printf '%s' "$code"
}

obs_bin_version() { # path [args...]
  local bin="$1"; shift
  if [[ -x "$bin" ]]; then
    "$bin" "$@" 2>/dev/null | head -1
  else
    echo "no instalado"
  fi
}

obs_status() {
  load_config || true
  OBS_SERVER_NAME="${NGINX_SERVER_NAME:-_}"

  echo
  divider
  echo "  OBSERVABILITY — STATUS"
  divider

  echo
  echo "Servicios (systemd):"
  local u state
  for u in "${OBS_UNITS[@]}"; do
    state="$(systemctl is-active "$u" 2>/dev/null || true)"
    [[ -z "$state" ]] && state="unknown"
    printf "  %-24s %s\n" "$u" "$state"
  done

  echo
  echo "Versiones instaladas:"
  printf "  %-12s %s\n" "prometheus" "$(obs_bin_version /usr/local/bin/prometheus --version)"
  printf "  %-12s %s\n" "loki"       "$(obs_bin_version /usr/local/bin/loki --version)"
  printf "  %-12s %s\n" "alloy"      "$(obs_bin_version /usr/local/bin/alloy --version)"
  printf "  %-12s %s\n" "grafana"    "$(obs_bin_version /usr/local/bin/grafana --version)"

  echo
  echo "Endpoints internos (loopback):"
  printf "  %-34s %s\n" "Prometheus /-/ready" "$(obs_curl_code http://127.0.0.1:9090/-/ready)"
  printf "  %-34s %s\n" "Loki /ready"          "$(obs_curl_code http://127.0.0.1:3100/ready)"
  printf "  %-34s %s\n" "Alloy /-/healthy"     "$(obs_curl_code http://127.0.0.1:12345/-/healthy)"
  printf "  %-34s %s\n" "Grafana /obs/login"   "$(obs_curl_code http://127.0.0.1:3000/obs/login)"

  echo
  echo "Scrape targets de Prometheus:"
  if command -v python3 >/dev/null 2>&1; then
    curl -s --max-time 5 http://127.0.0.1:9090/api/v1/targets 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for t in d.get("data",{}).get("activeTargets",[]):
        print("  {:<16} {:<10} {}".format(t.get("labels",{}).get("job","?"), t.get("health","?"), t.get("scrapeUrl","")))
except Exception as e:
    print("  (no disponible:", e, ")")
' || true
  else
    printf "  %s\n" "(python3 no disponible; usa: curl http://127.0.0.1:9090/api/v1/targets)"
  fi

  echo
  echo "Publicacion por nginx:"
  if [[ -n "$OBS_SERVER_NAME" && "$OBS_SERVER_NAME" != "_" ]]; then
    printf "  %-34s %s\n" "https://${OBS_SERVER_NAME}/obs/login" "$(obs_curl_code "https://${OBS_SERVER_NAME}/obs/login")"
    printf "  %-34s %s\n" "https://${OBS_SERVER_NAME}/collect"   "$(obs_curl_code -X POST "https://${OBS_SERVER_NAME}/collect")"
  else
    echo "  (dominio no configurado en config.env: NGINX_SERVER_NAME)"
  fi

  echo
  divider
}
