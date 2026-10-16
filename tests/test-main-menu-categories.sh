#!/usr/bin/env bash
# =============================================================================
# test-main-menu-categories.sh — pins the task-based main menu (IA reorg).
#
# The main menu groups work by "¿qué quiero hacer?" in 6 categories. Every
# entry must dispatch to the SAME module command the CLI exposes, so the CLI
# surface (`deploy <module> <action>`) and the runbooks never change. Category
# 6 (Avanzado) is dev-gated.
#
# The menu is driven with MENU_DRY_RUN=1, which prints the dispatch target
# instead of executing a command (no destructive side effects offline).
#
# Run: bash tests/test-main-menu-categories.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAIN="$ROOT/bin/menu.sh"

PASS=0
FAIL=0

dispatch_case() { # <name> <input(%b)> <expected-dispatch> [dev]
  local name="$1" input="$2" expected="$3" dev="${4:-}" out got
  if [[ -n "$dev" ]]; then
    out="$(printf '%b' "$input" | DEPLOY_DEV_MODE="$dev" MENU_DRY_RUN=1 bash "$MAIN" 2>&1)"
  else
    out="$(printf '%b' "$input" | MENU_DRY_RUN=1 bash "$MAIN" 2>&1)"
  fi
  got="$(printf '%s\n' "$out" | grep -m1 '^MENU-DISPATCH' | sed 's/[[:space:]]*$//')"
  if [[ "$got" == "$expected" ]]; then
    printf '  ok    %s -> %s\n' "$name" "$expected"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        esperado: %s\n        obtenido: %s\n' "$name" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "Menu principal por categorias (dispatch)"

# 1) ¿Como esta el sistema?  (3 acciones + Volver; main Salir = 6)
dispatch_case "cat1.1 estado simple"  '1\n1\n\n4\n6\n' "MENU-DISPATCH health simple"
dispatch_case "cat1.2 diagnostico"     '1\n2\n\n4\n6\n' "MENU-DISPATCH health full"
dispatch_case "cat1.3 historial"       '1\n3\n\n4\n6\n' "MENU-DISPATCH system audit"

# 2) Respaldos  (submenu: 1=configurar/ver, 2=restaurar, 3=Volver; Salir = 6)
dispatch_case "cat2.1 respaldos"        '2\n1\n\n3\n6\n' "MENU-DISPATCH database backup"
dispatch_case "cat2.2 restaurar"        '2\n2\n\n3\n6\n' "MENU-DISPATCH database restore"

# 3) Actualizar la aplicacion  (3 componentes -> menu del modulo; Salir = 6)
dispatch_case "cat3.1 backend"         '3\n1\n\n4\n6\n' "MENU-DISPATCH backend (menu)"
dispatch_case "cat3.2 frontend"        '3\n2\n\n4\n6\n' "MENU-DISPATCH frontend (menu)"
dispatch_case "cat3.3 observabilidad"  '3\n3\n\n4\n6\n' "MENU-DISPATCH observability (menu)"

# 4) Base de datos  (4 acciones + Volver; main Salir = 6)
dispatch_case "cat4.1 crear base"      '4\n1\n\n5\n6\n' "MENU-DISPATCH database create"
dispatch_case "cat4.2 verificar"       '4\n2\n\n5\n6\n' "MENU-DISPATCH database check"
dispatch_case "cat4.3 reset esquema"   '4\n3\n\n5\n6\n' "MENU-DISPATCH database reset-schema"
dispatch_case "cat4.4 rol Developer"   '4\n4\n\n5\n6\n' "MENU-DISPATCH database set-developer"

# 5) Configuracion y seguridad  (6 acciones + Volver; main Salir = 6)
dispatch_case "cat5.1 editar config"   '5\n1\n\n7\n6\n' "MENU-DISPATCH system edit-config"
dispatch_case "cat5.2 https interno"   '5\n2\n\n7\n6\n' "MENU-DISPATCH nginx configure-https"
dispatch_case "cat5.3 reload nginx"    '5\n3\n\n7\n6\n' "MENU-DISPATCH nginx reload"
dispatch_case "cat5.4 rotar RSA"       '5\n4\n\n7\n6\n' "MENU-DISPATCH system rotate-pem"
dispatch_case "cat5.5 rotar PII"       '5\n5\n\n7\n6\n' "MENU-DISPATCH system rotate-pii"
dispatch_case "cat5.6 servicios"       '5\n6\n\n7\n6\n' "MENU-DISPATCH system services"

# 6) Avanzado (dev ON; main Avanzado=6, Salir=7; cat Volver=4)
dispatch_case "cat6.1 letsencrypt"     '6\n1\n\n4\n7\n' "MENU-DISPATCH nginx configure-letsencrypt" 1
dispatch_case "cat6.2 release"         '6\n2\n\n4\n7\n' "MENU-DISPATCH release build" 1
dispatch_case "cat6.3 desinstalar"     '6\n3\n\n4\n7\n' "MENU-DISPATCH system uninstall" 1

# ── CLI preservation: `deploy <module> <action>` still resolves ──────────────
# Representative pair: the dispatch path reaches the real command script.
dc_out="$(bash -x "$ROOT/bin/deploy" database create </dev/null 2>&1)"
if [[ "$dc_out" == *"modules/database/commands/create.sh"* ]]; then
  printf '  ok    deploy database create -> resuelve commands/create.sh\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  deploy database create no resolvio el script esperado\n'; FAIL=$((FAIL + 1))
fi
# `deploy health full` corre el comando real.
hf_out="$(bash "$ROOT/bin/deploy" health full 2>&1 | head -3)"
if [[ "$hf_out" == *"FULL HEALTH CHECK"* ]]; then
  printf '  ok    deploy health full -> corre el health check completo\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  deploy health full no corrio\n'; FAIL=$((FAIL + 1))
fi
# Bare `deploy <module>` abre el menu del modulo (health sigue siendo simple).
dbm_out="$(printf '5\n' | bash "$ROOT/bin/deploy" database 2>&1)"
if [[ "$dbm_out" == *"DATABASE MENU"* ]]; then
  printf '  ok    deploy database (sin accion) -> menu del modulo\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  deploy database (sin accion) no abrio el menu\n'; FAIL=$((FAIL + 1))
fi
hh_out="$(bash "$ROOT/bin/deploy" health 2>&1 | head -1)"
if [[ "$hh_out" == "ESTADO DEL SISTEMA" ]]; then
  printf '  ok    deploy health (sin accion) -> estado simple\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  deploy health (sin accion) cambio de comportamiento\n'; FAIL=$((FAIL + 1))
fi

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
