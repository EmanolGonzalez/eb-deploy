#!/usr/bin/env bash
# =============================================================================
# modules/release/lib/release-common.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$RELEASE_BASE/core/logger.sh"
source "$RELEASE_BASE/core/input.sh"
source "$RELEASE_BASE/core/semver.sh"
