#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/health/commands/check.sh — Run healthcheck
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/health-common.sh"
source "$MODULE_DIR/../../core/health.sh"

COMPONENT="${1:-}"
MODE="${2:---soft}"

if [[ -z "$COMPONENT" ]]; then
  menu_select "Selecciona componente:" frontend backend
  COMPONENT="$MENU_SELECTION"
fi

run_healthcheck "$COMPONENT" "$MODE"
