#!/usr/bin/env bash
# =============================================================================
# core/config.sh — config.env management
# =============================================================================

CONFIG_FILE="${CONFIG_FILE:-/app/config/config.env}"

# Parse config.env into current scope (NO usa 'source' — config files se
# parsean, no se ejecutan, asi un valor con $(comando) NO se ejecuta).
load_config() {
  local require_vars="${1:-}"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "Archivo de configuracion no encontrado: $CONFIG_FILE"
    err "Ejecuta 'deploy system setup' para inicializar."
    return 1
  fi

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Saltear lineas vacias y comentarios.
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Match KEY=VALUE — KEY debe ser identificador valido de bash.
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Quitar comillas externas si las hay (simples o dobles).
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      # Asignar al scope global (printf -v evita eval y declare local).
      printf -v "$key" '%s' "$value"
    fi
  done < "$CONFIG_FILE"

  if [[ -n "$require_vars" ]]; then
    local missing=()
    for var in $require_vars; do
      [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
      err "Variables requeridas no definidas en $CONFIG_FILE:"
      for var in "${missing[@]}"; do
        err "  - $var"
      done
      return 1
    fi
  fi
}

# Update or add a key in config.env
update_config_value() {
  local key="$1" value="$2"
  local safe="${value//\\/\\\\}"; safe="${safe//\"/\\\"}"
  local tmp found=false
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^"${key}=" ]]; then
      printf '%s="%s"\n' "$key" "$safe" >> "$tmp"
      found=true
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$CONFIG_FILE"
  [[ "$found" == false ]] && printf '\n%s="%s"\n' "$key" "$safe" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

# Avisa (NO bloquea) si la connection string actual va a dar problemas de
# SSL contra servers internos sin cert valido. Requiere load_config previo.
# Devuelve 0 siempre (son advertencias). Usa 'warn' de core/logger.sh.
# Compartida entre setup-server.sh (validate_config) y edit-config.sh para que
# ambos caminos avisen igual.
warn_db_ssl_config() {
  local maria="${ConnectionStrings__MariaDB:-}"

  if [[ -n "$maria" && "$maria" != "CHANGE_ME" ]]; then
    if [[ "$maria" =~ [Ss]sl[Mm]ode=([Rr]equired|[Vv]erify[Cc][Aa]|[Vv]erify[Ff]ull) ]]; then
      warn "ConnectionStrings__MariaDB usa SslMode estricto (Required/VerifyCA/VerifyFull): FALLA en server interno sin SSL. Usa SslMode=Preferred o SslMode=None."
    fi
  fi

  return 0
}

# Read a single value from config.env
read_config_value() {
  local key="$1"
  grep -E "^${key}=" "$CONFIG_FILE" | cut -d= -f2- | tr -d '"' || true
}
