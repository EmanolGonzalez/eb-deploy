#!/usr/bin/env bash
# =============================================================================
# core/devmode.sh — Developer mode gate for the interactive menus.
#
# Signal (the ONE supported by this toolkit): the environment variable
#   DEPLOY_DEV_MODE=1
# When it is set, the menus ALSO show the development/risky actions
# (set-developer, run-schema, reset-schema, configure-letsencrypt, Release,
# uninstall). When it is NOT set, those entries are hidden from the menus.
#
# Hiding is a MENU-only concern: the underlying commands keep working when
# invoked directly (`deploy database run-schema`, `deploy system uninstall`,
# ...), because automation, tests and the release rehearsal depend on them.
#
# Usage:
#   DEPLOY_DEV_MODE=1 deploy menu
# =============================================================================

# deploy_dev_mode — returns 0 when developer mode is explicitly enabled.
deploy_dev_mode() {
  [[ "${DEPLOY_DEV_MODE:-}" == "1" ]]
}

# dev_mode_banner — prints the developer-mode note for a menu header, or
# nothing at all when developer mode is off. Always returns 0 so it can be
# dropped into a header without tripping `set -e`.
dev_mode_banner() {
  if deploy_dev_mode; then
    echo "*** MODO DESARROLLADOR ACTIVO ***"
  fi
  return 0
}
