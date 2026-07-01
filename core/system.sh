#!/usr/bin/env bash
# =============================================================================
# core/system.sh — System-level utilities
# =============================================================================

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}
