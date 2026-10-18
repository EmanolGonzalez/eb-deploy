#!/usr/bin/env bash
# =============================================================================
# test-observability-panels.sh — pins two live-test findings in the rendered
# observability stack:
#
#   1. Loki must pin frontend_worker.frontend_address to loopback, otherwise
#      the querier advertises the host IP and every query fails while writes
#      keep working (Grafana shows Loki as empty).
#   2. The starter dashboard must expose Loki log panels: API logs
#      (service_name=biometric-deliver-api) and browser exceptions
#      (service_name=eb-frontend, labelled by loki.process in the Alloy
#      pipeline because the Faro receiver defaults to unknown_service).
#
# Run: bash tests/test-observability-panels.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$ROOT/modules/observability/lib/render.sh"

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        esperado: %s\n        obtenido: %s\n' "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
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

# ── Render de artefactos (sin instalar nada) ────────────────────────────────
# shellcheck source=/dev/null
source "$RENDER"
OBS_LOKI_DATA=/var/lib/loki OBS_RETENTION_LOKI=720h \
  obs_render_loki_yml > "$TMP/loki.yml"
obs_render_alloy_config > "$TMP/alloy.alloy"
obs_render_grafana_dashboard > "$TMP/dash.json"

LOKI="$(cat "$TMP/loki.yml")"
ALLOY="$(cat "$TMP/alloy.alloy")"

# ── 1. Loki: frontend en loopback ───────────────────────────────────────────
check_contains "loki fija frontend_worker" "$LOKI" 'frontend_worker:'
check_contains "loki frontend en 127.0.0.1:9096" "$LOKI" 'frontend_address: 127.0.0.1:9096'

# ── 2. Alloy: etiqueta los eventos Faro como eb-frontend ────────────────────
check_contains "alloy crea loki.process faro_labels" "$ALLOY" 'loki.process "faro_labels"'
check_contains "alloy etiqueta service_name=eb-frontend" "$ALLOY" 'service_name = "eb-frontend"'
check_contains "faro.receiver enruta al process" "$ALLOY" 'logs   = [loki.process.faro_labels.receiver]'

# ── 3. Dashboard: paneles Loki (API + excepciones del navegador) ────────────
if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
panels = {p["id"]: p for p in d["panels"]}
assert panels[5]["datasource"]["uid"] == "loki"
assert panels[6]["datasource"]["uid"] == "loki"
assert panels[5]["targets"][0]["expr"] == chr(123) + "service_name=\"biometric-deliver-api\"" + chr(125)
assert panels[6]["targets"][0]["expr"] == chr(123) + "service_name=\"eb-frontend\"" + chr(125) + " |= \"kind=exception\""
' "$TMP/dash.json" 2>/dev/null; then
  printf '  ok    dashboard con paneles Loki (API + Faro)\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  dashboard sin los paneles/consultas esperadas\n'; FAIL=$((FAIL + 1))
fi

# ── Resumen ─────────────────────────────────────────────────────────────────
echo
if [[ "$FAIL" -eq 0 ]]; then
  printf 'OK: %d/%d checks\n' "$PASS" "$((PASS + FAIL))"
  exit 0
fi
printf 'FALLOS: %d de %d\n' "$FAIL" "$((PASS + FAIL))"
exit 1
