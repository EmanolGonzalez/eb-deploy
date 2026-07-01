#!/usr/bin/env bash
# NO 'set -e': queremos recorrer TODO y reportar todos los problemas juntos.
set -uo pipefail
# =============================================================================
# modules/system/commands/lint.sh — Verificacion estatica de los scripts bash
#
# Falla (exit 1) si encuentra alguno de estos problemas, ANTES de deployar:
#   1. Error de sintaxis (bash -n)
#   2. 'local' fuera de funcion  -> "local: can only be used in a function"
#   3. Conexion a BD sin trust SSL (sqlcmd sin -C / mariadb directo sin
#      --ssl-verify-server-cert=0) -> falla contra servers internos sin SSL
#
# Solo usa herramientas presentes en el server: bash, find, awk, grep.
# (No usa rg/bat/etc para funcionar offline en el servidor interno.)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$BASE_DIR/core/logger.sh"

ISSUES=0

echo ""
divider
echo "  LINT — verificacion de scripts bash"
echo "  Base: $BASE_DIR"
divider

# Lista de scripts (excluye .git).
mapfile -t SCRIPTS < <(find "$BASE_DIR" -name '*.sh' -not -path '*/.git/*' | sort)

# ── 1) SINTAXIS ──────────────────────────────────────────────────────────────
step "1/3 — Sintaxis (bash -n)"
syntax_bad=0
for f in "${SCRIPTS[@]}"; do
  if ! err_out="$(bash -n "$f" 2>&1)"; then
    err "Sintaxis: ${f#"$BASE_DIR"/}"
    printf '%s\n' "$err_out" | sed 's/^/      /'
    syntax_bad=$((syntax_bad + 1))
  fi
done
if [[ $syntax_bad -eq 0 ]]; then ok "Sintaxis OK en ${#SCRIPTS[@]} scripts."; else ISSUES=$((ISSUES + syntax_bad)); fi

# ── 2) 'local' FUERA DE FUNCION ──────────────────────────────────────────────
step "2/3 — 'local' fuera de funcion"
local_bad=0
for f in "${SCRIPTS[@]}"; do
  # awk: cuenta profundidad de llaves (ignorando comentarios, \${...} y strings)
  # y marca cualquier 'local' a profundidad 0.
  out="$(awk '
    {
      s = $0
      sub(/#.*/, "", s)                 # comentarios
      gsub(/\$\{[^}]*\}/, "", s)         # ${...}
      gsub(/"[^"]*"/, "", s)             # "..."
      gsub(/'\''[^'\'']*'\''/, "", s)    # '\''...'\''
      o = gsub(/\{/, "{", s); c = gsub(/\}/, "}", s)
      if (s ~ /(^|;|then|do|else)[[:space:]]*local[[:space:]]/ && depth <= 0)
        printf "%d: %s\n", NR, $0
      depth += o - c
      if (depth < 0) depth = 0
    }' "$f")"
  if [[ -n "$out" ]]; then
    err "'local' fuera de funcion en ${f#"$BASE_DIR"/}:"
    printf '%s\n' "$out" | sed 's/^/      /'
    local_bad=$((local_bad + 1))
  fi
done
if [[ $local_bad -eq 0 ]]; then ok "Ningun 'local' fuera de funcion."; else ISSUES=$((ISSUES + local_bad)); fi

# ── 3) TRUST SSL EN CONEXIONES A SERVERS INTERNOS ────────────────────────────
step "3/3 — Trust SSL (servers internos)"
ssl_bad=0

# sqlcmd con -S (invocacion real) pero sin -C.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  err "sqlcmd sin -C (no confia en cert interno): $hit"
  ssl_bad=$((ssl_bad + 1))
done < <(grep -rnE 'sqlcmd .* -S ' "$BASE_DIR" --include='*.sh' 2>/dev/null \
           | grep -v '/lint.sh:' | grep -v ' -C ' | grep -vE ':[[:space:]]*#')

# Cliente mariadb/mysql/dump directo (-h) sin --ssl-verify-server-cert.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  err "mariadb/mysql directo sin --ssl-verify-server-cert=0: $hit"
  ssl_bad=$((ssl_bad + 1))
done < <(grep -rnE '(\$client|\bmariadb\b|\bmysql\b|dump_cmd) .* -h ' "$BASE_DIR" --include='*.sh' 2>/dev/null \
           | grep -v '/lint.sh:' | grep -v 'ssl-verify-server-cert' | grep -vE 'docker exec|:[[:space:]]*#|info ')

if [[ $ssl_bad -eq 0 ]]; then ok "Conexiones a BD confian en servers internos."; else ISSUES=$((ISSUES + ssl_bad)); fi

# ── RESULTADO ────────────────────────────────────────────────────────────────
echo ""
divider
if [[ $ISSUES -eq 0 ]]; then
  echo "  LINT OK ✓"
  divider
  ok "Los scripts estan sanos. Listo para empaquetar/deployar."
  echo ""
  exit 0
fi
echo "  LINT FALLO — $ISSUES problema(s) ✗"
divider
err "Corregi los problemas de arriba ANTES de deployar al server."
echo ""
exit 1
