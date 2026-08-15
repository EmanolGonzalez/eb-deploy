#!/usr/bin/env bash
# =============================================================================
# core/health.sh — Health check utilities with dependency validation
# =============================================================================

# Run application healthcheck inline (no external script).
# Usage: run_healthcheck COMPONENT [--soft|--strict]
#   COMPONENT: backend | frontend
#   Default mode: --soft
run_healthcheck() {
  local component="${1:-backend}"
  local mode="${2:---soft}"
  local soft_mode=true
  case "$mode" in
    --soft)   soft_mode=true ;;
    --strict) soft_mode=false ;;
    *)        err "run_healthcheck: modo desconocido '$mode' (use --soft o --strict)"; return 2 ;;
  esac

  _hc_fail_or_warn() {
    local message="$1"
    if [[ "$soft_mode" == true ]]; then
      warn "$message"
      return 0
    fi
    err "$message"
    return 1
  }

  if [[ "$component" == "frontend" ]]; then
    local frontend_current_link="/app/frontend/current"
    local frontend_index_file="${frontend_current_link}/index.html"

    log "Checking frontend current symlink $frontend_current_link"
    if [[ ! -L "$frontend_current_link" ]]; then
      _hc_fail_or_warn "frontend current symlink not found." || return 1
      [[ "$soft_mode" == true ]] && return 0
    fi

    log "Checking frontend artifact $frontend_index_file"
    if [[ ! -f "$frontend_index_file" ]]; then
      _hc_fail_or_warn "frontend index file not found in current release." || return 1
      [[ "$soft_mode" == true ]] && return 0
    fi

    ok "Healthcheck frontend passed."
    return 0
  fi

  if [[ "$component" != "backend" ]]; then
    err "run_healthcheck: componente desconocido '$component' (use backend o frontend)"
    return 2
  fi

  local app_name="backend"
  local backend_release_dir="/app/backend/current"
  local max_retries="${HEALTHCHECK_RETRIES:-20}"
  local sleep_seconds="${HEALTHCHECK_SLEEP_SECONDS:-3}"

  local -a ports=()
  if [[ -n "${APP_PORT:-}" ]]; then
    ports+=("$APP_PORT")
  fi
  if [[ -n "${BACKEND_PORTS:-}" ]]; then
    local p
    for p in ${BACKEND_PORTS//,/ }; do
      ports+=("$p")
    done
  fi
  if [[ -d "$backend_release_dir" ]]; then
    local p
    while IFS= read -r p; do
      ports+=("$p")
    done < <(grep -h -oE 'http://localhost:[0-9]+' "$backend_release_dir"/appsettings*.json 2>/dev/null | sed -E 's#.*:([0-9]+)$#\1#')
  fi
  ports+=("5000")

  local -a port_candidates
  mapfile -t port_candidates < <(printf '%s\n' "${ports[@]}" | awk '/^[0-9]+$/{print}' | awk '!seen[$0]++')
  if [[ ${#port_candidates[@]} -eq 0 ]]; then
    port_candidates=("5000")
  fi

  log "Candidate backend ports: ${port_candidates[*]}"

  log "Checking if service $app_name is active"
  if ! systemctl is-active --quiet "$app_name"; then
    _hc_fail_or_warn "service $app_name is not active." || return 1
    [[ "$soft_mode" == true ]] && return 0
  fi

  local health_paths=("/api/health" "/health" "/healthz")
  local healthy=false
  local attempt port path endpoint

  for ((attempt=1; attempt<=max_retries; attempt++)); do
    if ! systemctl is-active --quiet "$app_name"; then
      log "Attempt $attempt/$max_retries: service not active yet"
      sleep "$sleep_seconds"
      continue
    fi

    for port in "${port_candidates[@]}"; do
      if ss -tulnp | grep -q ":${port}\\b"; then
        log "Attempt $attempt/$max_retries: port $port is listening"
        for path in "${health_paths[@]}"; do
          endpoint="http://localhost:${port}${path}"
          if curl -fs --max-time 3 "$endpoint" > /dev/null; then
            ok "Health endpoint OK: $endpoint"
            healthy=true
            break 3
          fi
        done
      fi
    done

    sleep "$sleep_seconds"
  done

  if [[ "$healthy" != true ]]; then
    _hc_fail_or_warn "backend did not become healthy after $max_retries attempts." || {
      echo "Tip: check logs with: journalctl -u backend -n 60 --no-pager" >&2
      return 1
    }
    [[ "$soft_mode" == true ]] && return 0
  fi

  ok "Healthcheck backend passed."
  return 0
}

# Print full deployment status report.
# Usage: print_status [--json|--help]
print_status() {
  local output_format="text"
  case "${1:-}" in
    --json) output_format="json" ;;
    --help)
      echo "Usage: print_status [--json]"
      return 0
      ;;
    "") ;;
    *)
      err "print_status: argumento desconocido '${1}'"
      return 2
      ;;
  esac

  # Parsear el config.env, NO 'source'-arlo: un valor con $(comando) o backticks
  # NO debe ejecutarse. load_config (core/config.sh) parsea de forma segura.
  CONFIG_FILE="/app/config/config.env" load_config 2>/dev/null || true

  local exit_code=0
  local frontend_version=""
  local backend_version=""
  local frontend_current_link="/app/frontend/current"
  local backend_current_link="/app/backend/current"
  local frontend_files_ok=false
  local frontend_http_ok=false
  local nginx_running=false
  local backend_service_ok=false
  local backend_port_ok=false
  local backend_health_ok=false

  _st_say() {
    local level="$1"; shift
    [[ "$output_format" != "text" ]] && return 0
    case "$level" in
      ok)   ok "$*" ;;
      warn) warn "$*" ;;
      err)  err "$*" ;;
      info) info "$*" ;;
    esac
  }

  _st_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
  }

  _st_check_symlink_version() {
    local component="$1"
    local current_link="/app/${component}/current"

    if [[ -L "$current_link" ]]; then
      local target version
      target="$(readlink "$current_link")"
      version="$(basename "$target")"
      if [[ "$component" == "frontend" ]]; then
        frontend_version="$version"
      else
        backend_version="$version"
      fi
      _st_say ok "$component version: $version"
    else
      if [[ "$component" == "frontend" ]]; then
        frontend_version="unknown"
      else
        backend_version="unknown"
      fi
      _st_say warn "$component version: current symlink not found ($current_link)"
      exit_code=1
    fi
  }

  _st_check_frontend_running() {
    local frontend_index="/app/frontend/current/index.html"

    if [[ -f "$frontend_index" ]]; then
      frontend_files_ok=true
      _st_say ok "frontend files: present ($frontend_index)"
    else
      _st_say err "frontend files: missing ($frontend_index)"
      exit_code=1
    fi

    if systemctl is-active --quiet nginx; then
      nginx_running=true
      _st_say ok "nginx service: running"
    else
      _st_say err "nginx service: not running"
      exit_code=1
    fi

    if curl -fsS "http://localhost/" >/dev/null; then
      frontend_http_ok=true
      _st_say ok "frontend http: http://localhost/"
    else
      _st_say warn "frontend http: no 200 at http://localhost/"
      exit_code=1
    fi
  }

  _st_check_backend_running() {
    local backend_health_url=""
    local backend_health_status=""
    local port_ok=false
    local attempt candidate
    local health_candidates=(
      "${BACKEND_HEALTH_ENDPOINT:-http://localhost:5000/api/health}"
      "http://localhost:5000/health"
      "http://localhost:5000/healthz"
      "http://localhost/api/health"
    )

    if systemctl is-active --quiet backend; then
      backend_service_ok=true
      _st_say ok "backend service: running"
    else
      _st_say err "backend service: not running"
      exit_code=1
    fi

    for attempt in 1 2 3 4 5; do
      if ss -tulnp | grep -q ':5000'; then
        port_ok=true
        break
      fi
      sleep 2
    done

    if [[ "$port_ok" == true ]]; then
      backend_port_ok=true
      _st_say ok "backend port 5000: listening"
    else
      _st_say err "backend port 5000: not listening"
      exit_code=1
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
      _st_say ok "backend health: $backend_health_url"
    else
      _st_say warn "backend health: no known endpoint returned 200 (checked ${health_candidates[*]})"
    fi

    if [[ "$backend_service_ok" == true ]] && [[ -L "/app/backend/current" ]]; then
      local backend_target
      backend_target="$(readlink "/app/backend/current")"
      _st_say info "backend current release path: $backend_target"
    fi
  }

  _st_say info "Deployment status"
  _st_check_symlink_version "frontend"
  _st_check_symlink_version "backend"
  _st_check_frontend_running
  _st_check_backend_running

  if [[ "$exit_code" -eq 0 ]]; then
    _st_say info "Overall status: healthy"
  else
    _st_say info "Overall status: issues detected"
  fi

  if [[ "$output_format" == "json" ]]; then
    local overall_status="issues"
    [[ "$exit_code" -eq 0 ]] && overall_status="healthy"

    printf '{\n'
    printf '  "overallStatus": "%s",\n' "$(_st_json_escape "$overall_status")"
    printf '  "frontend": {\n'
    printf '    "version": "%s",\n' "$(_st_json_escape "$frontend_version")"
    printf '    "currentLink": "%s",\n' "$(_st_json_escape "$frontend_current_link")"
    printf '    "filesPresent": %s,\n' "$frontend_files_ok"
    printf '    "httpOk": %s,\n' "$frontend_http_ok"
    printf '    "nginxRunning": %s\n' "$nginx_running"
    printf '  },\n'
    printf '  "backend": {\n'
    printf '    "version": "%s",\n' "$(_st_json_escape "$backend_version")"
    printf '    "currentLink": "%s",\n' "$(_st_json_escape "$backend_current_link")"
    printf '    "serviceRunning": %s,\n' "$backend_service_ok"
    printf '    "port5000Listening": %s,\n' "$backend_port_ok"
    printf '    "healthOk": %s\n' "$backend_health_ok"
    printf '  }\n'
    printf '}\n'
  fi

  return "$exit_code"
}

# Check database connectivity (MariaDB).
# Servers internos sin SSL: mariadb --ssl-verify-server-cert=0.
check_db_connection() {
  local maria="${ConnectionStrings__MariaDB:-}"

  if [[ -z "$maria" ]]; then
    warn "No hay cadena de conexion configurada. Se omite validacion de BD."
    return 0
  fi

  log "Validando conexion a MariaDB..."

  local client=""
  command -v mariadb &>/dev/null && client="mariadb"
  [[ -z "$client" ]] && command -v mysql &>/dev/null && client="mysql"
  if [[ -z "$client" ]]; then
    warn "mariadb/mysql no disponible. Se omite validacion de MariaDB."
    return 0
  fi
  local server port user password database
  server="$(echo "$maria"   | sed -nE 's/.*[Ss]erver=([^;]+).*/\1/p')"
  port="$(echo "$maria"     | sed -nE 's/.*[Pp]ort=([^;]+).*/\1/p')"
  user="$(echo "$maria"     | sed -nE 's/.*[Uu]ser=([^;]+).*/\1/p')"
  password="$(echo "$maria" | sed -nE 's/.*[Pp]assword=([^;]+).*/\1/p')"
  database="$(echo "$maria" | sed -nE 's/.*[Dd]atabase=([^;]+).*/\1/p')"
  port="${port:-3306}"

  if "$client" --ssl-verify-server-cert=0 -h "$server" -P "$port" -u"$user" -p"$password" "${database:-}" -e "SELECT 1" &>/dev/null; then
    ok "Conexion a MariaDB exitosa ($server:$port)"
    return 0
  fi
  err "No se pudo conectar a MariaDB ($server:$port)"
  return 1
}

# Check if external services are reachable (Tribunal services)
check_external_services() {
  local scope="${TribunalServices__NetworkScope:-}"
  if [[ -z "$scope" ]]; then
    return 0
  fi

  log "Validando servicios del tribunal (scope: $scope)..."

  # Comparacion case-insensitive: el config.env usa "Internal"/"External"
  # (mayuscula). Comparar contra "internal" en minuscula nunca matcheaba.
  local servers=()
  if [[ "${scope,,}" == "internal" ]]; then
    servers=("servicios.te" "services.te" "10.10.10.1")
  else
    servers=("servicios.te.gob.pa" "services.te.gob.pa")
  fi

  local reachable=0
  for srv in "${servers[@]}"; do
    if ping -c 1 -W 2 "$srv" &>/dev/null; then
      ok "Servicio alcanzable: $srv"
      ((reachable++))
    fi
  done

  if [[ $reachable -eq 0 ]]; then
    warn "No se pudo alcanzar ningun servicio del tribunal."
    warn "Esto puede ser normal en entornos de desarrollo o si los servicios estan offline."
  fi

  return 0
}

# Run healthcheck with auto-rollback on failure
run_healthcheck_or_rollback() {
  local component="$1" previous_version="$2" previous_release_dir="$3"

  log "Ejecutando healthcheck de $component..."

  if run_healthcheck "$component" --strict; then
    ok "Healthcheck pasado."
    return 0
  fi

  err "Healthcheck FALLO. Iniciando rollback automatico..."

  if [[ -z "$previous_version" ]]; then
    err "No hay version anterior guardada. Rollback manual requerido."
    return 1
  fi

  warn "Restaurando version anterior: $previous_version"

  if [[ ! -d "$previous_release_dir" ]]; then
    err "Directorio de version anterior no encontrado: $previous_release_dir"
    return 1
  fi

  local install_base="${INSTALL_BASE:-/app}"
  ln -sfn "$previous_release_dir" "${install_base}/${component}/current"
  ok "Symlink restaurado a $previous_version"

  if [[ "$component" == "backend" ]]; then
    systemctl restart backend || true
  fi

  log "Verificando healthcheck de la version restaurada..."
  if run_healthcheck "$component" --soft; then
    warn "Rollback a $previous_version completado."
  else
    err "El healthcheck tambien fallo en la version anterior. Intervencion manual requerida."
  fi

  return 1
}
