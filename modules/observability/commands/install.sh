#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/observability/commands/install.sh
# Install Grafana + Prometheus + Loki + Alloy as native systemd services.
# Usage: deploy observability install [--non-interactive] [--yes]
#                                     [--admin-user U] [--admin-password P]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/observability-common.sh"
source "$MODULE_DIR/lib/render.sh"
source "$MODULE_DIR/lib/install-steps.sh"

obs_install "$@"
