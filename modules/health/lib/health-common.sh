#!/usr/bin/env bash
# =============================================================================
# modules/health/lib/health-common.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HEALTH_BASE/core/logger.sh"
source "$HEALTH_BASE/core/input.sh"
source "$HEALTH_BASE/core/config.sh"
