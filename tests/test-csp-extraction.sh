#!/usr/bin/env bash
# =============================================================================
# test-csp-extraction.sh — pins how the CSP style-src hash is extracted.
#
# The hash has to cover the loader's <style> block EXACTLY. Cover less and the
# browser blocks the whole block, so the app loads with no loader styles at
# all; cover something else and the same thing happens.
#
# This exists because a silent partial extraction already shipped: the block
# was located with rindex("<style>"), searching backwards, and a comment INSIDE
# the CSS that mentioned "<style>" moved the start marker. The hash was then
# computed over the last 1941 bytes of a 4639-byte block. Nothing failed, no
# script errored, the deploy reported success — only the browser noticed,
# asking for the hash of the real block.
#
# Run: bash bs_deploy/tests/test-csp-extraction.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSP_SH="$SCRIPT_DIR/../core/csp.sh"

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Runs the perl program lifted VERBATIM out of csp.sh instead of a copy of it.
# A copy is a second source of truth that silently rots: this suite would keep
# passing against a paraphrase while the deploy ran something else. The awk
# range pulls the program between the perl invocation and its closing quote.
extract() {
  local program
  program="$(awk "/perl -0777 -ne '/{f=1; next} f&&/^  ' \"\\\$index_file\"/{exit} f" "$CSP_SH")"
  if [[ -z "$program" ]]; then
    echo "no se pudo leer el programa perl desde csp.sh" >&2
    return 2
  fi
  perl -0777 -ne "$program" "$1"
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n     esperado: %s\n     obtenido: %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "Extraccion del bloque <style> para la CSP"

# --- The regression that shipped -------------------------------------------
cat > "$TMP/inner-mention.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <style>
      .a { color: red; }
      /* el hash cubre este <style>, pero no un atributo */
      .b { color: blue; }
    </style>
  </head>
</html>
HTML
check "un <style> mencionado DENTRO del CSS no corta el bloque" \
  "$(printf '\n      .a { color: red; }\n      /* el hash cubre este <style>, pero no un atributo */\n      .b { color: blue; }\n    ')" \
  "$(extract "$TMP/inner-mention.html")"

# --- The case the old rindex was written for -------------------------------
# Los comentarios HTML se eliminan antes de buscar: una mencion previa no puede
# mover el inicio, y una mencion dentro del CSS queda despues de la apertura.
cat > "$TMP/comment-before.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <!-- este bloque <style> lo hashea el deploy -->
    <style>
      .a { color: red; }
    </style>
  </head>
</html>
HTML
check "un <style> mencionado ANTES en un comentario HTML tampoco confunde" \
  "$(printf '\n      .a { color: red; }\n    ')" \
  "$(extract "$TMP/comment-before.html")"

# --- Opening tag with attributes -------------------------------------------
cat > "$TMP/attrs.html" <<'HTML'
<html><head><style type="text/css">.a{color:red}</style></head></html>
HTML
check "la etiqueta de apertura puede traer atributos" \
  ".a{color:red}" \
  "$(extract "$TMP/attrs.html")"

# --- Failure modes must FAIL, never return an empty string ------------------
printf '<html><head></head></html>\n' > "$TMP/none.html"
if extract "$TMP/none.html" >/dev/null 2>&1; then
  printf '  FAIL  sin bloque <style> tiene que salir con error\n'
  FAIL=$((FAIL + 1))
else
  printf '  ok    sin bloque <style> sale con error (no cadena vacia)\n'
  PASS=$((PASS + 1))
fi

printf '<html><head><style>.a{}\n' > "$TMP/unclosed.html"
if extract "$TMP/unclosed.html" >/dev/null 2>&1; then
  printf '  FAIL  un <style> sin cerrar tiene que salir con error\n'
  FAIL=$((FAIL + 1))
else
  printf '  ok    un <style> sin cerrar sale con error\n'
  PASS=$((PASS + 1))
fi

# --- The empty hash that looks valid ---------------------------------------
# Hashing nothing yields a perfectly well-formed hash that blocks everything.
# csp.sh refuses an empty block for exactly this reason.
EMPTY_HASH="$(printf '' | openssl dgst -sha256 -binary | openssl base64 -A)"
check "el hash de la cadena vacia es el conocido (por eso se rechaza)" \
  "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" \
  "$EMPTY_HASH"

# --- csp.sh still contains the guard rails ---------------------------------
if grep -q 'tmp_block' "$CSP_SH" && grep -q '! -s "\$tmp_block"' "$CSP_SH"; then
  printf '  ok    csp.sh sigue extrayendo a archivo y rechazando el bloque vacio\n'
  PASS=$((PASS + 1))
else
  printf '  FAIL  csp.sh perdio la extraccion a archivo o el chequeo de vacio\n'
  FAIL=$((FAIL + 1))
fi

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
