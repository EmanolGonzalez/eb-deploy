#!/usr/bin/env bash
# =============================================================================
# modules/nginx/lib/nginx-common.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$NGINX_BASE/core/logger.sh"
source "$NGINX_BASE/core/input.sh"
source "$NGINX_BASE/core/config.sh"
source "$NGINX_BASE/core/system.sh"
