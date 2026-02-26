#!/usr/bin/env bash
set -e

OUTPUT_FORMAT="text"
if [[ "${1:-}" == "--json" ]]; then
  OUTPUT_FORMAT="json"
elif [[ "${1:-}" == "--help" ]]; then
  echo "Usage: bash status.sh [--json]"
  exit 0
fi

ok() {
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "\033[1;32mOK\033[0m  $*"
  fi
}

warn() {
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "\033[1;33mWARN\033[0m $*"
  fi
}

err() {
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "\033[1;31mERR\033[0m  $*"
  fi
}

info() {
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "\033[1;34m==>\033[0m $*"
  fi
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

EXIT_CODE=0
FRONTEND_VERSION=""
BACKEND_VERSION=""
FRONTEND_CURRENT_LINK="/app/frontend/current"
BACKEND_CURRENT_LINK="/app/backend/current"

FRONTEND_FILES_OK=false
FRONTEND_HTTP_OK=false
NGINX_RUNNING=false

BACKEND_SERVICE_OK=false
BACKEND_PORT_OK=false
BACKEND_HEALTH_OK=false

check_symlink_version() {
  local component="$1"
  local current_link="/app/${component}/current"

  if [[ -L "$current_link" ]]; then
    local target version
    target="$(readlink "$current_link")"
    version="$(basename "$target")"
    if [[ "$component" == "frontend" ]]; then
      FRONTEND_VERSION="$version"
    else
      BACKEND_VERSION="$version"
    fi
    ok "$component version: $version"
  else
    if [[ "$component" == "frontend" ]]; then
      FRONTEND_VERSION="unknown"
    else
      BACKEND_VERSION="unknown"
    fi
    warn "$component version: current symlink not found ($current_link)"
    EXIT_CODE=1
  fi
}

check_backend_running() {
  local backend_health_ok=false
  local backend_health_url=""
  local backend_health_status=""
  local health_candidates=(
    "${BACKEND_HEALTH_ENDPOINT:-http://localhost:5000/api/health}"
    "http://localhost:5000/health"
    "http://localhost:5000/healthz"
    "http://localhost/api/health"
  )

  if systemctl is-active --quiet backend; then
    BACKEND_SERVICE_OK=true
    ok "backend service: running"
  else
    err "backend service: not running"
    EXIT_CODE=1
  fi

  if ss -tulnp | grep -q ':5000'; then
    BACKEND_PORT_OK=true
    ok "backend port 5000: listening"
  else
    err "backend port 5000: not listening"
    EXIT_CODE=1
  fi

  for candidate in "${health_candidates[@]}"; do
    backend_health_status="$(curl -s -o /dev/null -w '%{http_code}' "$candidate" || true)"
    if [[ "$backend_health_status" == "200" ]]; then
      backend_health_ok=true
      backend_health_url="$candidate"
      break
    fi
  done

  if [[ "$backend_health_ok" == true ]]; then
    BACKEND_HEALTH_OK=true
    ok "backend health: $backend_health_url"
  else
    warn "backend health: no known endpoint returned 200 (checked ${health_candidates[*]})"
  fi

  if [[ "$BACKEND_SERVICE_OK" == true ]] && [[ -L "/app/backend/current" ]]; then
    local backend_target
    backend_target="$(readlink "/app/backend/current")"
    if systemctl show backend -p FragmentPath --value >/dev/null 2>&1; then
      info "backend current release path: $backend_target"
    fi
  fi
}

check_frontend_running() {
  local frontend_index="/app/frontend/current/dist/index.html"

  if [[ -f "$frontend_index" ]]; then
    FRONTEND_FILES_OK=true
    ok "frontend files: present ($frontend_index)"
  else
    err "frontend files: missing ($frontend_index)"
    EXIT_CODE=1
  fi

  if systemctl is-active --quiet nginx; then
    NGINX_RUNNING=true
    ok "nginx service: running"
  else
    err "nginx service: not running"
    EXIT_CODE=1
  fi

  if curl -fsS "http://localhost/" >/dev/null; then
    FRONTEND_HTTP_OK=true
    ok "frontend http: http://localhost/"
  else
    warn "frontend http: no 200 at http://localhost/"
    EXIT_CODE=1
  fi
}

info "Deployment status"
check_symlink_version "frontend"
check_symlink_version "backend"
check_frontend_running
check_backend_running

if [[ "$EXIT_CODE" -eq 0 ]]; then
  info "Overall status: healthy"
else
  info "Overall status: issues detected"
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  OVERALL_STATUS="issues"
  if [[ "$EXIT_CODE" -eq 0 ]]; then
    OVERALL_STATUS="healthy"
  fi

  printf '{\n'
  printf '  "overallStatus": "%s",\n' "$(json_escape "$OVERALL_STATUS")"
  printf '  "frontend": {\n'
  printf '    "version": "%s",\n' "$(json_escape "$FRONTEND_VERSION")"
  printf '    "currentLink": "%s",\n' "$(json_escape "$FRONTEND_CURRENT_LINK")"
  printf '    "filesPresent": %s,\n' "$FRONTEND_FILES_OK"
  printf '    "httpOk": %s,\n' "$FRONTEND_HTTP_OK"
  printf '    "nginxRunning": %s\n' "$NGINX_RUNNING"
  printf '  },\n'
  printf '  "backend": {\n'
  printf '    "version": "%s",\n' "$(json_escape "$BACKEND_VERSION")"
  printf '    "currentLink": "%s",\n' "$(json_escape "$BACKEND_CURRENT_LINK")"
  printf '    "serviceRunning": %s,\n' "$BACKEND_SERVICE_OK"
  printf '    "port5000Listening": %s,\n' "$BACKEND_PORT_OK"
  printf '    "healthOk": %s\n' "$BACKEND_HEALTH_OK"
  printf '  }\n'
  printf '}\n'
fi

exit "$EXIT_CODE"
