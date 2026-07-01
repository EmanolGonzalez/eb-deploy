#!/usr/bin/env bash
# =============================================================================
# core/db.sh — Database connection management via environment variables
#
# Seguridad: NO modificamos appsettings.json. Los secretos van solo en config.env
# y se inyectan via systemd EnvironmentFile.
# =============================================================================

# Log which connection strings are present (after load_config has run).
# Safe no-op if neither is set.
load_db_connection_if_exists() {
  if [[ -n "${ConnectionStrings__SqlServer:-}" ]]; then
    log "ConnectionStrings__SqlServer cargada desde $CONFIG_FILE"
  fi
  if [[ -n "${ConnectionStrings__MariaDB:-}" ]]; then
    log "ConnectionStrings__MariaDB cargada desde $CONFIG_FILE"
  fi
}

# Parse connection string into readable summary
connection_summary() {
  local cs="$1"
  local server database user
  server="$(echo "$cs"   | sed -nE 's/.*[Ss]erver=([^;]+).*/\1/p')"
  database="$(echo "$cs" | sed -nE 's/.*([Dd]atabase|[Ii]nitial [Cc]atalog)=([^;]+).*/\2/p')"
  user="$(echo "$cs"     | sed -nE 's/.*([Uu]ser [Ii][Dd]|[Uu]id)=([^;]+).*/\2/p')"
  [[ -z "$server"   ]] && server="(desconocido)"
  [[ -z "$database" ]] && database="(desconocida)"
  [[ -z "$user"     ]] && user="(integrated/no user)"
  printf 'server=%s | db=%s | user=%s' "$server" "$database" "$user"
}

# Update a connection string in config.env
# This updates the EnvironmentFile that systemd loads — appsettings.json is NOT touched.
update_db_connection() {
  local value="$1"
  update_config_value "ConnectionStrings__SqlServer" "$value"
  ok "ConnectionStrings__SqlServer actualizada en $CONFIG_FILE"
  log "El cambio se aplicara en el proximo reinicio del servicio backend."
}

# Prompt for new connection string and save it
prompt_new_db_connection_string() {
  local value
  read -rsp "ConnectionStrings__SqlServer: " value
  echo
  if [[ -z "$value" ]]; then
    err "La cadena de conexion no puede estar vacia."
    return 1
  fi
  update_db_connection "$value"
}

# Ensure DB connection for backend component
# In the new model, we just confirm the value exists in config.env.
# The backend reads it via EnvironmentFile — no sed needed.
ensure_db_connection_for_backend() {
  local component="$1"
  [[ "$component" != "backend" ]] && return

  if [[ -n "${ConnectionStrings__SqlServer:-}" ]]; then
    log "Cadena de conexion actual: $(connection_summary "$ConnectionStrings__SqlServer")"
    menu_select "Que deseas hacer con la cadena de conexion?" \
      "Usar cadena guardada" "Ingresar otra"
    if [[ "$MENU_SELECTION" == "Ingresar otra" ]]; then
      prompt_new_db_connection_string
    fi
    return
  fi

  if [[ -n "${ConnectionStrings__MariaDB:-}" ]]; then
    log "Cadena MariaDB configurada: ${ConnectionStrings__MariaDB}"
    menu_select "Que deseas hacer con la cadena de conexion?" \
      "Usar cadena guardada" "Ingresar SQL Server"
    if [[ "$MENU_SELECTION" == "Ingresar SQL Server" ]]; then
      prompt_new_db_connection_string
    fi
    return
  fi

  menu_select "No hay cadena de conexion configurada para backend." \
    "Ingresar SQL Server" "Ingresar MariaDB" "Continuar sin definir"
  case "$MENU_SELECTION" in
    "Ingresar SQL Server") prompt_new_db_connection_string ;;
    "Ingresar MariaDB")
      local value
      read -rsp "ConnectionStrings__MariaDB: " value
      echo
      if [[ -z "$value" ]]; then
        err "La cadena de conexion no puede estar vacia."
        return 1
      fi
      update_config_value "ConnectionStrings__MariaDB" "$value"
      ok "ConnectionStrings__MariaDB guardada en $CONFIG_FILE"
      ;;
  esac
}
