#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/health/commands/simple.sh — One-touch, plain-language system status
#
# Default `deploy health` view: the operator runs ONE thing and instantly knows
# the state, with no JSON and no engineering jargon. The technical commands
# (check, full, status, set-endpoint) stay available for diagnostics.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/health-common.sh"
source "$MODULE_DIR/lib/simple.sh"

# Best-effort config load: BACKEND_HEALTH_ENDPOINT points the health probe.
# Sin config, la vista simple igual funciona contra los defaults locales.
load_config 2>/dev/null || true

health_simple
