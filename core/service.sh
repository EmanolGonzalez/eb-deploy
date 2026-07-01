#!/usr/bin/env bash
# =============================================================================
# core/service.sh — systemd service management
# =============================================================================

# Restart a service
restart_service() {
  local service_name="$1"
  log "Reiniciando servicio $service_name..."
  if systemctl restart "$service_name"; then
    ok "Servicio $service_name reiniciado."
  else
    err "Fallo al reiniciar $service_name."
    return 1
  fi
}

# Restart a service, ignoring errors (soft restart)
restart_service_soft() {
  local service_name="$1"
  systemctl restart "$service_name" || true
}

# Stop a service
stop_service() {
  local service_name="$1"
  log "Deteniendo servicio $service_name..."
  if systemctl stop "$service_name"; then
    ok "Servicio $service_name detenido."
  else
    err "Fallo al detener $service_name."
    return 1
  fi
}

# Start a service
start_service() {
  local service_name="$1"
  log "Iniciando servicio $service_name..."
  if systemctl start "$service_name"; then
    ok "Servicio $service_name iniciado."
  else
    err "Fallo al iniciar $service_name."
    return 1
  fi
}

# Check if a service is active
service_is_active() {
  systemctl is-active --quiet "$1"
}

# Restart backend service
restart_backend() {
  if [[ "$1" == "--soft" ]]; then
    restart_service_soft "backend"
  else
    restart_service "backend"
  fi
}
