#!/usr/bin/env bash
set -e

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  read -rp "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

remove_if_exists() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf "$path"
    log "Removed: $path"
  fi
}

require_root

log "Uninstall will remove deployment artifacts and service config."
log "Evidence folders will be preserved: /app/evidence and /app/evidences"

if ! confirm "Are you sure you want to uninstall the application from this VM?"; then
  log "Uninstall cancelled."
  exit 0
fi

if systemctl list-unit-files | grep -q '^backend.service'; then
  log "Stopping backend service..."
  systemctl stop backend || true
  systemctl disable backend || true
  remove_if_exists "/etc/systemd/system/backend.service"
  systemctl daemon-reload
  systemctl reset-failed || true
fi

if [[ -L /etc/nginx/sites-enabled/app || -f /etc/nginx/sites-available/app ]]; then
  log "Removing nginx app site..."
  remove_if_exists "/etc/nginx/sites-enabled/app"
  remove_if_exists "/etc/nginx/sites-available/app"

  if [[ -f /etc/nginx/sites-available/default ]]; then
    ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  fi

  nginx -t || true
  systemctl reload nginx || true
fi

log "Removing deployment directories (preserving evidence folders)..."
remove_if_exists "/app/frontend"
remove_if_exists "/app/backend"
remove_if_exists "/app/releases/frontend"
remove_if_exists "/app/releases/backend"

log "Removing script/runtime config files (except evidence data)..."
remove_if_exists "/app/config/storage.conf"
remove_if_exists "/app/config/db-connection.txt"
remove_if_exists "/app/config/backend-health-endpoint.txt"
remove_if_exists "/app/config/nginx-server-name.txt"

if [[ -d "/app/evidence" ]]; then
  log "Preserved: /app/evidence"
fi

if [[ -d "/app/evidences" ]]; then
  log "Preserved: /app/evidences"
fi

log "Uninstall completed."
