#!/usr/bin/env bash
# =============================================================================
# test-retired-rollback.sh — pins the two upgrade lessons from the T3 test:
#
#   1. install_component registra la version previa ANTES de cambiar el
#      symlink, para que 'rollback' funcione tras un upgrade hecho con
#      'install' (el flujo real del cliente).
#   2. cleanup_retired_files borra SOLO las rutas listadas en
#      setup/retired-files.txt, sin escapar de INSTALL_BASE ni tocar otros
#      componentes.
#
# Run: bash tests/test-retired-rollback.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FS="$ROOT/core/filesystem.sh"
DEP="$ROOT/core/deployment.sh"

PASS=0
FAIL=0
TMP="$(mktemp -d)" || { printf 'FATAL: fallo mktemp -d: no se puede preparar el directorio temporal de pruebas.\n' >&2; exit 1; }
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

# ── 1. Wiring: install_component guarda la previa y limpia obsoletos ────────
install_body="$(awk '/^install_component\(\)/{f=1} f{print} f&&/^}$/{exit}' "$DEP")"
check_contains "install registra version previa" "$install_body" 'save_previous_version "$component"'
check_contains "install limpia obsoletos" "$install_body" 'cleanup_retired_files "$component"'

prev_line="$(printf '%s\n' "$install_body" | grep -n 'save_previous_version' | head -1 | cut -d: -f1)"
link_line="$(printf '%s\n' "$install_body" | grep -n 'update_symlink' | head -1 | cut -d: -f1)"
check "previa se guarda antes del symlink" "yes" "$( ((prev_line < link_line)) && echo yes || echo no )"

# ── 2. cleanup_retired_files: solo lo listado, sin escapar ──────────────────
mkdir -p "$TMP/base/setup" "$TMP/app/backend/current" "$TMP/app/frontend"
cat > "$TMP/base/setup/retired-files.txt" <<'EOF'
# comentario que debe ignorarse
backend run-schema.sh
backend current/run-schema.sh
* legacy-top.sh
backend ../escape.sh
frontend other-component.sh
backend no-existe-jamas.sh
EOF
# Linea CRLF (editor Windows) — debe interpretarse igual.
printf 'backend crlf-file.sh\r\n' >> "$TMP/base/setup/retired-files.txt"

touch "$TMP/app/backend/run-schema.sh" \
      "$TMP/app/backend/current/run-schema.sh" \
      "$TMP/app/legacy-top.sh" \
      "$TMP/app/backend/crlf-file.sh" \
      "$TMP/app/backend/keep-me.txt" \
      "$TMP/app/frontend/other-component.sh"
touch "$TMP/app/escape.sh"   # candidato real de la ruta con ..: no debe tocarse

INSTALL_BASE="$TMP/app" BASE_DIR="$TMP/base"
# shellcheck source=/dev/null
source "$ROOT/core/logger.sh"
# shellcheck source=/dev/null
source "$FS"
cleanup_retired_files backend > /dev/null

check "retirado: backend/run-schema.sh" "no" "$([[ -e "$TMP/app/backend/run-schema.sh" ]] && echo si || echo no)"
check "retirado: backend/current/run-schema.sh" "no" "$([[ -e "$TMP/app/backend/current/run-schema.sh" ]] && echo si || echo no)"
check "retirado: top-level (*)" "no" "$([[ -e "$TMP/app/legacy-top.sh" ]] && echo si || echo no)"
check "retirado: linea CRLF" "no" "$([[ -e "$TMP/app/backend/crlf-file.sh" ]] && echo si || echo no)"
check "se conserva: no listado" "si" "$([[ -e "$TMP/app/backend/keep-me.txt" ]] && echo si || echo no)"
check "se conserva: otro componente" "si" "$([[ -e "$TMP/app/frontend/other-component.sh" ]] && echo si || echo no)"
check "se conserva: ruta con .. ignorada" "si" "$([[ -e "$TMP/app/escape.sh" ]] && echo si || echo no)"

# ── Resumen ─────────────────────────────────────────────────────────────────
echo
if [[ "$FAIL" -eq 0 ]]; then
  printf 'OK: %d/%d checks\n' "$PASS" "$((PASS + FAIL))"
  exit 0
fi
printf 'FALLOS: %d de %d\n' "$FAIL" "$((PASS + FAIL))"
exit 1
