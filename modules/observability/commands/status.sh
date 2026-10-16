#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/observability/commands/status.sh
# Show service state, versions, endpoints and scrape targets.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/observability-common.sh"
source "$MODULE_DIR/lib/status.sh"

obs_status "$@"
