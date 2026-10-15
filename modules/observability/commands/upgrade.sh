#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/observability/commands/upgrade.sh
# Re-resolve and (re)install the observability stack from assets/online.
# Usage: deploy observability upgrade [--non-interactive] [--yes]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/observability-common.sh"
source "$MODULE_DIR/lib/render.sh"
source "$MODULE_DIR/lib/install-steps.sh"

obs_install --upgrade "$@"
