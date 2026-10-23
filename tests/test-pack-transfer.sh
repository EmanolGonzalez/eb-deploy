#!/usr/bin/env bash
# =============================================================================
# test-pack-transfer.sh — pins scripts/pack-transfer.sh
#
# The transfer package is split: deploy.rar carries the toolkit only (no
# assets/), and each populated assets group travels in its own
# deploy_<grupo>_assets.rar that extracts back to assets/<grupo>/ at the repo
# root. --all produces a single assets bundle; SHA256SUMS.txt covers every
# produced part.
#
# The packaging runs against a throw-away fixture root, so the real assets/
# tree is never read or written:
#   <fixture>/scripts/pack-transfer.sh   (copy of the real script)
#   <fixture>/assets/{alpha,beta}/...    (groups with one file each)
#   <fixture>/{top.txt,bin/deploy,...}   (toolkit bits)
#   <fixture>/{.git,node_modules,transfer}/  (must be excluded)
#
# Run: bash tests/test-pack-transfer.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACK="$ROOT/scripts/pack-transfer.sh"

PASS=0
FAIL=0

ok()   { printf '  ok    %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)" || { printf 'FATAL: fallo mktemp -d: no se puede preparar el directorio temporal de pruebas.\n' >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

RAR="$(command -v rar || true)"
TOOLS_TGZ=""
for f in "$ROOT/assets/tools"/rarlinux*.tar.gz; do
  if [[ -f "$f" ]]; then TOOLS_TGZ="$f"; break; fi
done

if [[ -z "$RAR" && -z "$TOOLS_TGZ" ]]; then
  echo "SKIP pack-transfer: no hay 'rar' ni assets/tools/rarlinux*.tar.gz"
  exit 0
fi

echo "pack-transfer (empaquetado partido)"

# ── Fixture root ─────────────────────────────────────────────────────────────
FIX="$TMP/fixture con espacios"
mkdir -p "$FIX/scripts" "$FIX/assets/alpha" "$FIX/assets/beta" "$FIX/bin" \
         "$FIX/node_modules/pkg" "$FIX/transfer" "$FIX/.git"
cp "$PACK" "$FIX/scripts/pack-transfer.sh"
if [[ -z "$RAR" && -n "$TOOLS_TGZ" ]]; then
  mkdir -p "$FIX/assets/tools"
  cp "$TOOLS_TGZ" "$FIX/assets/tools/"
fi
printf '#!/usr/bin/env bash\necho deploy\n' > "$FIX/bin/deploy"
printf 'alpha\n' > "$FIX/assets/alpha/alpha.txt"
printf 'beta\n'  > "$FIX/assets/beta/beta.txt"
printf '{"version":"test"}\n' > "$FIX/assets/manifest.json"
printf 'top\n' > "$FIX/top.txt"
printf 'nodep\n' > "$FIX/node_modules/pkg/index.js"
printf 'junk\n' > "$FIX/transfer/junk.txt"
printf 'git\n'  > "$FIX/.git/HEAD"

if [[ -z "$RAR" ]]; then
  # The script extracted its own rar from the fixture assets/tools tarball.
  RAR="$FIX/.rar-for-listing"
  for f in "$FIX/assets/tools"/rarlinux*.tar.gz; do
    [[ -f "$f" ]] || continue
    tar -xzf "$f" -C "$TMP"
    if [[ -f "$TMP/rar/rar" ]]; then
      chmod +x "$TMP/rar/rar"
      RAR="$TMP/rar/rar"
    fi
    break
  done
fi

# ── CLI contract ─────────────────────────────────────────────────────────────
help_out="$(bash "$PACK" --help 2>&1)"; help_rc=$?
if [[ $help_rc -eq 0 && "$help_out" == *"--out"* && "$help_out" == *"--only"* ]]; then
  ok "--help sale 0 y documenta las opciones"
else
  fail "--help no cumple (rc=$help_rc)"
fi

bash "$PACK" --opcion-invalida >/dev/null 2>&1; rc=$?
if [[ $rc -eq 2 ]]; then
  ok "opcion desconocida -> exit 2"
else
  fail "opcion desconocida devolvio $rc (esperado 2)"
fi

bash "$PACK" --out >/dev/null 2>&1; rc=$?
if [[ $rc -eq 2 ]]; then
  ok "--out sin valor -> exit 2"
else
  fail "--out sin valor devolvio $rc (esperado 2)"
fi

bash "$PACK" --all --only alpha >/dev/null 2>&1; rc=$?
if [[ $rc -eq 2 ]]; then
  ok "--all con --only -> exit 2"
else
  fail "--all con --only devolvio $rc (esperado 2)"
fi

# ── --only: toolkit + una parte, en una ruta con espacios ───────────────────
OUT="$TMP/out dir"
if bash "$FIX/scripts/pack-transfer.sh" --only alpha --out "$OUT" >"$TMP/only.log" 2>&1; then
  ok "--only alpha termina 0"
else
  fail "--only alpha fallo"; sed 's/^/        /' "$TMP/only.log"
fi

for f in deploy.rar deploy_alpha_assets.rar SHA256SUMS.txt; do
  if [[ -f "$OUT/$f" ]]; then ok "genera $f"; else fail "falta $f"; fi
done

deploy_list="$("$RAR" lt "$OUT/deploy.rar" 2>&1)"
if [[ "$deploy_list" == *"Name: top.txt"* && "$deploy_list" == *"Name: bin/deploy"* ]]; then
  ok "deploy.rar lleva el toolkit"
else
  fail "deploy.rar no lleva el toolkit"
fi
if [[ "$deploy_list" != *"Name: assets"* ]]; then
  ok "deploy.rar NO lleva assets/"
else
  fail "deploy.rar incluye assets/"
fi
if [[ "$deploy_list" != *".git"* && "$deploy_list" != *"node_modules"* && "$deploy_list" != *"transfer/"* ]]; then
  ok "deploy.rar excluye .git, node_modules y transfer/"
else
  fail "deploy.rar incluye rutas excluidas"
fi

alpha_list="$("$RAR" lt "$OUT/deploy_alpha_assets.rar" 2>&1)"
if [[ "$alpha_list" == *"Name: assets/alpha/alpha.txt"* ]]; then
  ok "la parte de alpha conserva assets/alpha/..."
else
  fail "la parte de alpha no conserva assets/alpha/..."
fi
if [[ "$alpha_list" != *"assets/beta"* ]]; then
  ok "la parte de alpha no arrastra otros grupos"
else
  fail "la parte de alpha arrastra assets/beta"
fi

checksum_out="$(cd "$OUT" && sha256sum -c SHA256SUMS.txt 2>&1)"; checksum_rc=$?
if [[ $checksum_rc -eq 0 && "$checksum_out" == *"deploy.rar: OK"* && "$checksum_out" == *"deploy_alpha_assets.rar: OK"* ]]; then
  ok "SHA256SUMS.txt valida todas las partes"
else
  fail "SHA256SUMS.txt no valida (rc=$checksum_rc)"
fi

# ── Modo por defecto: una parte por grupo ───────────────────────────────────
OUT2="$TMP/default"
if bash "$FIX/scripts/pack-transfer.sh" --out "$OUT2" >"$TMP/default.log" 2>&1; then
  if [[ -f "$OUT2/deploy_alpha_assets.rar" && -f "$OUT2/deploy_beta_assets.rar" ]]; then
    ok "sin flags genera una parte por grupo existente"
  else
    fail "sin flags faltan partes por grupo"
  fi
else
  fail "modo por defecto fallo"; sed 's/^/        /' "$TMP/default.log"
fi

# ── --all: un solo archivo con todos los assets ─────────────────────────────
OUT3="$TMP/all"
if bash "$FIX/scripts/pack-transfer.sh" --all --out "$OUT3" >"$TMP/all.log" 2>&1; then
  ok "--all termina 0"
else
  fail "--all fallo"; sed 's/^/        /' "$TMP/all.log"
fi
if [[ -f "$OUT3/deploy_assets_all.rar" ]]; then
  all_list="$("$RAR" lt "$OUT3/deploy_assets_all.rar" 2>&1)"
  if [[ "$all_list" == *"assets/alpha/alpha.txt"* && "$all_list" == *"assets/beta/beta.txt"* ]]; then
    ok "--all junta todos los grupos en deploy_assets_all.rar"
  else
    fail "--all no junta todos los grupos"
  fi
else
  fail "--all no genero deploy_assets_all.rar"
fi

# ── Grupo inexistente: falla (no inventa una parte vacia) ───────────────────
bash "$FIX/scripts/pack-transfer.sh" --only no-existe --out "$TMP/nope" >/dev/null 2>&1; rc=$?
if [[ $rc -ne 0 ]]; then
  ok "--only con grupo inexistente falla"
else
  fail "--only con grupo inexistente devolvio 0"
fi

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
