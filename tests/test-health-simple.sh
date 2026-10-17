#!/usr/bin/env bash
# =============================================================================
# test-health-simple.sh — pins the one-touch operator health view (PART B).
#
# The operator must run ONE thing and read a plain-language verdict: no JSON,
# no jargon, colors only on a TTY, exit 0 when everything is OK and 1 when
# anything fails, and the observability line omitted when that module is not
# installed.
#
# The per-component probes are stubbed so both the OK and the FALLA variants are
# pinned offline, without touching the real host.
#
# Run: bash tests/test-health-simple.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/modules/health/lib/simple.sh"

PASS=0
FAIL=0

check() { # <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        esperado: %s\n        obtenido: %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
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

# Baseline: everything healthy, observability NOT installed.
stub_all_ok() {
  _hs_web_ok() { return 0; }
  _hs_app_ok() { return 0; }
  _hs_db_status() { echo "Healthy"; }
  _hs_obs_installed() { return 1; }
}

echo "Vista simple de salud (deploy health)"

# ── Variant OK ────────────────────────────────────────────────────────────────
stub_all_ok
out="$(health_simple)"; rc=$?
check "OK: exit code 0" "0" "$rc"
check_contains "OK: titulo"               "$out" "ESTADO DEL SISTEMA"
check_contains "OK: pagina web"           "$out" "[OK]   Página web"
check_contains "OK: aplicacion"           "$out" "[OK]   Aplicación"
check_contains "OK: base de datos"        "$out" "[OK]   Base de datos"
check_contains "OK: veredicto"            "$out" "→ TODO FUNCIONANDO"
if [[ "$out" != *"Observabilidad"* ]]; then
  printf '  ok    OK: omite Observabilidad si no esta instalada\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  OK: no deberia listar Observabilidad\n'; FAIL=$((FAIL + 1))
fi
if [[ "$out" != *$'\033['* ]]; then
  printf '  ok    OK: sin colores cuando stdout no es TTY\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  OK: emitio codigos ANSI sin TTY\n'; FAIL=$((FAIL + 1))
fi

# ── Variant FALLA (solo BD) + observabilidad instalada y OK ───────────────────
stub_all_ok
_hs_db_status() { echo "Unhealthy"; }
_hs_obs_installed() { return 0; }
_hs_obs_ok() { return 0; }
out="$(health_simple)"; rc=$?
check "FALLA: exit code 1" "1" "$rc"
check_contains "FALLA: marca la BD"        "$out" "[FALLA] Base de datos"
check_contains "FALLA: pagina web OK"      "$out" "[OK]   Página web"
check_contains "FALLA: observabilidad OK"  "$out" "[OK]   Observabilidad"
check_contains "FALLA: veredicto accionable" "$out" "→ QUÉ HACER:"
if [[ "$out" != *"TODO FUNCIONANDO"* ]]; then
  printf '  ok    FALLA: no dice TODO FUNCIONANDO\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  FALLA: no debe decir TODO FUNCIONANDO\n'; FAIL=$((FAIL + 1))
fi

# ── Sin JSON ni jerga tecnica ─────────────────────────────────────────────────
stub_all_ok
out="$(health_simple)"
if [[ "$out" != *"{"* && "$out" != *"endpoint"* && "$out" != *"soft"* ]]; then
  printf '  ok    sin JSON ni jerga (endpoint/soft)\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  la salida simple contiene JSON o jerga tecnica\n'; FAIL=$((FAIL + 1))
fi

# ── _hs_db_status: parsea el check sql_server del payload /api/health ─────────
# Restore the real probes (the stubs above replaced them) before parsing tests.
# shellcheck source=/dev/null
source "$ROOT/modules/health/lib/simple.sh"

_hs_health_payload() { printf '%s' '{"status":"Degraded","checks":[{"name":"cache","status":"Healthy"},{"name":"sql_server","status":"Unhealthy","duration":12.3,"description":"No se pudo conectar","data":{"Provider":"MariaDB"}}],"totalDuration":20}'; }
check "parse: sql_server Unhealthy" "Unhealthy" "$(_hs_db_status)"

_hs_health_payload() { printf '%s' '{"status":"Healthy","checks":[{"name":"sql_server","status":"Healthy","duration":1.0},{"name":"cache","status":"Healthy"}]}'; }
check "parse: sql_server Healthy" "Healthy" "$(_hs_db_status)"

_hs_health_payload() { printf '%s' '<html>nginx fallback</html>'; }
check "parse: payload no-JSON -> vacio" "" "$(_hs_db_status)"

_hs_health_payload() { return 1; }
check "parse: sin payload -> vacio" "" "$(_hs_db_status)"

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
