#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/nginx/commands/reload.sh — Reload Nginx
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/nginx-common.sh"

log "Probando configuracion de Nginx..."
if nginx -t; then
  ok "Configuracion valida."
  log "Reiniciando Nginx..."
  systemctl restart nginx
  ok "Nginx reiniciado."
else
  err "Configuracion de Nginx invalida."
  exit 1
fi
