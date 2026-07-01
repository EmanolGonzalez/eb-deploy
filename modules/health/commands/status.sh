#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/health/commands/status.sh — System status report
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/health-common.sh"
source "$MODULE_DIR/../../core/health.sh"

print_status "$@"
