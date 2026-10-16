#!/usr/bin/env bash
# =============================================================================
# test-dev-mode-menus.sh — pins the menu curation (PART A).
#
# The client's operator must NOT see development/risky actions in the menus;
# they appear only with DEPLOY_DEV_MODE=1. The underlying commands stay
# reachable when invoked directly (documented by `deploy <mod> --help`).
#
# The menus are exercised through their real entrypoints with piped input: the
# assertion is on what the operator actually sees, not on a paraphrased list.
#
# Run: bash tests/test-dev-mode-menus.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

run_menu() { # <script> <input-number> [DEPLOY_DEV_MODE]
  local script="$1" input="$2" dev="${3:-}"
  if [[ -n "$dev" ]]; then
    printf '%s\n' "$input" | DEPLOY_DEV_MODE="$dev" bash "$script" 2>&1
  else
    printf '%s\n' "$input" | bash "$script" 2>&1
  fi
}

check_contains() { # <name> <haystack> <needle>
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        falta: %s\n' "$name" "$needle"; FAIL=$((FAIL + 1))
  fi
}

check_absent() { # <name> <haystack> <needle>
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        no deberia aparecer: %s\n' "$name" "$needle"; FAIL=$((FAIL + 1))
  fi
}

echo "Curation de menus por developer mode"

# ── Database ─────────────────────────────────────────────────────────────────
DB="$ROOT/modules/database/menu.sh"
off="$(run_menu "$DB" 3)"
on="$(run_menu "$DB" 7 1)"
check_absent     "database OFF: oculta set-developer"    "$off" "Asignar rol Developer"
check_absent     "database OFF: oculta run-schema"       "$off" "Ejecutar esquema de la base de datos"
check_absent     "database OFF: oculta reset-schema"     "$off" "Resetear esquema"
check_contains   "database OFF: mantiene check"          "$off" "Verificar conexion a BD"
check_contains   "database OFF: mantiene backup"         "$off" "Correr backup ahora"
check_contains   "database ON: muestra set-developer"    "$on"  "Asignar rol Developer"
check_contains   "database ON: muestra run-schema"       "$on"  "Ejecutar esquema de la base de datos"
check_contains   "database ON: muestra reset-schema"     "$on"  "Resetear esquema"
check_contains   "database ON: banner dev"               "$on"  "MODO DESARROLLADOR ACTIVO"
check_absent     "database OFF: sin banner dev"          "$off" "MODO DESARROLLADOR ACTIVO"

# ── System ───────────────────────────────────────────────────────────────────
SYS="$ROOT/modules/system/menu.sh"
off="$(run_menu "$SYS" 8)"
on="$(run_menu "$SYS" 9 1)"
check_absent     "system OFF: oculta uninstall"          "$off" "Uninstall"
check_contains   "system OFF: mantiene setup"            "$off" "Setup server"
check_contains   "system OFF: mantiene rotate-pii"       "$off" "Rotar PII Hash Key"
check_contains   "system ON: muestra uninstall"          "$on"  "Uninstall"
check_contains   "system ON: banner dev"                 "$on"  "MODO DESARROLLADOR ACTIVO"

# ── Nginx ────────────────────────────────────────────────────────────────────
NGX="$ROOT/modules/nginx/menu.sh"
off="$(run_menu "$NGX" 3)"
on="$(run_menu "$NGX" 4 1)"
check_absent     "nginx OFF: oculta letsencrypt"         "$off" "Let's Encrypt"
check_contains   "nginx OFF: mantiene configure-https"   "$off" "Configurar HTTPS interno"
check_contains   "nginx OFF: mantiene reload"            "$off" "Reload Nginx"
check_contains   "nginx ON: muestra letsencrypt"         "$on"  "Let's Encrypt"
check_contains   "nginx ON: banner dev"                  "$on"  "MODO DESARROLLADOR ACTIVO"

# ── Main menu: Release entry ─────────────────────────────────────────────────
MAIN="$ROOT/bin/menu.sh"
off="$(run_menu "$MAIN" 8)"
on="$(run_menu "$MAIN" 9 1)"
check_absent     "main OFF: oculta Release"              "$off" "Release"
check_contains   "main OFF: mantiene Observability"      "$off" "Observability"
check_contains   "main OFF: mantiene Salir"              "$off" "Salir"
check_contains   "main ON: muestra Release"              "$on"  "Release"
check_contains   "main ON: banner dev"                   "$on"  "MODO DESARROLLADOR ACTIVO"

# ── Hidden commands stay reachable directly ──────────────────────────────────
# (routing/docs reachability; live invocation is part of the VM rehearsal)
for spec in "database/set-developer" "database/run-schema" "database/reset-schema" \
            "nginx/configure-letsencrypt" "system/uninstall" "release/build"; do
  if [[ -f "$ROOT/modules/${spec%/*}/commands/${spec#*/}.sh" ]]; then
    printf '  ok    comando directo presente: %s\n' "$spec"; PASS=$((PASS + 1))
  else
    printf '  FAIL  comando directo ausente: %s\n' "$spec"; FAIL=$((FAIL + 1))
  fi
done
help_out="$(bash "$ROOT/bin/deploy" database --help 2>&1)"
check_contains   "deploy database --help lista run-schema" "$help_out" "run-schema"
check_contains   "deploy database --help lista reset-schema" "$help_out" "reset-schema"

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
