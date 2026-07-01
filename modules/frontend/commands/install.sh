#!/usr/bin/env bash
set -euo pipefail
# modules/frontend/commands/install.sh — Install frontend from /app/artifacts/frontend.rar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$DEPLOY_BASE/core/deployment.sh"

install_component "frontend"
