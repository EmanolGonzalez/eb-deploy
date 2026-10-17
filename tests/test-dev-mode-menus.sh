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

check_equal() { # <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        esperado identico:\n%s\n        obtenido:\n%s\n' "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

echo "Curation de menus por developer mode"

# ── Database: NO dev gating (todas las acciones son del operador) ────────────
DB="$ROOT/modules/database/menu.sh"
off="$(run_menu "$DB" 7)"
on="$(run_menu "$DB" 7 1)"
check_contains   "database OFF: muestra respaldos"            "$off" "Respaldos (configurar / ver los existentes)"
check_contains   "database OFF: muestra restaurar"           "$off" "Restaurar un respaldo"
check_contains   "database OFF: muestra create"             "$off" "Crear base de datos (si fue eliminada)"
check_contains   "database OFF: muestra check"              "$off" "Verificar conexion a BD"
check_contains   "database OFF: muestra reset-schema"       "$off" "Reset de esquema"
check_contains   "database OFF: muestra set-developer"      "$off" "Asignar rol Developer"
check_contains   "database ON:  muestra create"             "$on"  "Crear base de datos (si fue eliminada)"
check_contains   "database ON:  muestra reset-schema"       "$on"  "Reset de esquema"
check_contains   "database ON:  muestra set-developer"      "$on"  "Asignar rol Developer"
check_absent     "database: run-schema ya no esta en el menu" "$off" "Ejecutar esquema"
check_absent     "database ON: sin banner dev (sin gating)" "$on"  "MODO DESARROLLADOR ACTIVO"
check_equal      "database OFF == ON (sin gating dev)"      "$off" "$on"

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

# ── Main menu: categorias por tarea ──────────────────────────────────────────
MAIN="$ROOT/bin/menu.sh"
off="$(run_menu "$MAIN" 6)"       # dev OFF: Salir = opcion 6
on="$(run_menu "$MAIN" 7 1)"      # dev ON : Salir = opcion 7
check_contains   "main OFF: categoria 1 (estado)"        "$off" "¿Cómo está el sistema?"
check_contains   "main OFF: categoria 2 (respaldos)"     "$off" "Respaldos"
check_contains   "main OFF: categoria 3 (actualizar)"    "$off" "Actualizar la aplicación"
check_contains   "main OFF: categoria 4 (base de datos)" "$off" "Base de datos"
check_contains   "main OFF: categoria 5 (config)"        "$off" "Configuración y seguridad"
check_contains   "main OFF: mantiene Salir"              "$off" "Salir"
check_absent     "main OFF: oculta Avanzado (dev)"       "$off" "Avanzado"
check_absent     "main OFF: sin banner dev"              "$off" "MODO DESARROLLADOR ACTIVO"
check_contains   "main ON: muestra Avanzado (dev)"       "$on"  "Avanzado"
check_contains   "main ON: banner dev"                   "$on"  "MODO DESARROLLADOR ACTIVO"
check_contains   "main ON: mantiene las 5 categorias"    "$on"  "Configuración y seguridad"

# ── Hidden commands stay reachable directly ──────────────────────────────────
# (routing/docs reachability; live invocation is part of the VM rehearsal)
for spec in "nginx/configure-letsencrypt" "system/uninstall" "release/build"; do
  if [[ -f "$ROOT/modules/${spec%/*}/commands/${spec#*/}.sh" ]]; then
    printf '  ok    comando dev-gated presente: %s\n' "$spec"; PASS=$((PASS + 1))
  else
    printf '  FAIL  comando dev-gated ausente: %s\n' "$spec"; FAIL=$((FAIL + 1))
  fi
done

# Comandos del operador (NO gateados): siempre presentes.
for spec in "database/backup" "database/restore" "database/create" "database/check" \
            "database/reset-schema" "database/set-developer"; do
  if [[ -f "$ROOT/modules/${spec%/*}/commands/${spec#*/}.sh" ]]; then
    printf '  ok    comando operador presente: %s\n' "$spec"; PASS=$((PASS + 1))
  else
    printf '  FAIL  comando operador ausente: %s\n' "$spec"; FAIL=$((FAIL + 1))
  fi
done

help_out="$(bash "$ROOT/bin/deploy" database --help 2>&1)"
check_contains   "deploy database --help lista create"        "$help_out" "create"
check_contains   "deploy database --help lista restore"       "$help_out" "restore"
check_contains   "deploy database --help lista reset-schema"  "$help_out" "reset-schema"
check_contains   "deploy database --help lista set-developer" "$help_out" "set-developer"
check_absent     "deploy database --help NO lista run-schema" "$help_out" "run-schema"

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
