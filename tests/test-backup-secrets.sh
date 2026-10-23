#!/usr/bin/env bash
# =============================================================================
# test-backup-secrets.sh — pins `system backup-secrets` (DOC-23).
#
# The DB backups are only half of the recovery story: the decryption keys live
# in /app/config/config.env and /app/secrets/. This suite pins the encrypted,
# verifiable secrets backup: source validation, the passphrase gate, the /app
# destination rejection, the artifact (name, mode, SHA-256, restore command),
# and --verify (checksum + test-decrypt listing NAMES only, never contents).
#
# Offline: sources are pointed at a sandbox tree via CONFIG_FILE/SECRETS_DIR
# (same override pattern core/config.sh uses). The /root default output dir is
# NOT exercised (needs root); tests always pass --out.
#
# Run: bash tests/test-backup-secrets.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BS="$ROOT/modules/system/commands/backup-secrets.sh"

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

check_absent() { # <name> <haystack> <needle>
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        no deberia aparecer: %s\n' "$name" "$needle"; FAIL=$((FAIL + 1))
  fi
}

# ── Fixtures: sandbox sources (fake keys; values NUNCA deben imprimirse) ─────
make_sources() { # <config-passphrase-value> [extra-config-lines...]
  local pass="$1"; shift
  mkdir -p "$TMP/src/config" "$TMP/src/secrets"
  {
    printf 'Backup__EncryptionPassphrase="%s"\n' "$pass"
    printf 'PiiEncryption__HashKeyBase64="FAKE-HASH-KEY-VALUE"\n'
    printf 'ConnectionStrings__MariaDB="Server=db;Database=ema;User=u;Password=FAKE-DB-PASS;"\n'
  } > "$TMP/src/config/config.env"
  printf -- '-----BEGIN PRIVATE KEY-----\nFAKE-PEM-BODY\n-----END PRIVATE KEY-----\n' \
    > "$TMP/src/secrets/rsa-private-key.pem"
}

make_sources "testpass-DO-NOT-PRINT"

run() { # <config-file> <secrets-dir> [args...]
  CONFIG_FILE="$1" SECRETS_DIR="$2" bash "$BS" "${@:3}"
}

echo "system backup-secrets (respaldo cifrado de secretos)"

# ── 1. Command present + help ────────────────────────────────────────────────
[[ -f "$BS" ]] && { printf '  ok    backup-secrets.sh existe\n'; PASS=$((PASS + 1)); } || { printf '  FAIL  backup-secrets.sh ausente\n'; FAIL=$((FAIL + 1)); }
help_out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --help 2>&1)"; help_rc=$?
check "help: exit 0" "0" "$help_rc"
check_contains "help: --out"          "$help_out" "--out"
check_contains "help: --verify"       "$help_out" "--verify"
check_contains "help: primitiva"      "$help_out" "aes-256-cbc"
check_contains "help: config.env"     "$help_out" "config.env"
check_contains "help: secrets/"       "$help_out" "secrets/"

# ── 2. Argument parsing errors ───────────────────────────────────────────────
run "$TMP/src/config/config.env" "$TMP/src/secrets" --bogus >/dev/null 2>&1
check "opcion desconocida -> exit 2" "2" "$?"
run "$TMP/src/config/config.env" "$TMP/src/secrets" --out >/dev/null 2>&1
check "--out sin valor -> exit 2" "2" "$?"
run "$TMP/src/config/config.env" "$TMP/src/secrets" --verify >/dev/null 2>&1
check "--verify sin valor -> exit 2" "2" "$?"
run "$TMP/src/config/config.env" "$TMP/src/secrets" --out "$TMP/out" --verify "$TMP/x.enc" >/dev/null 2>&1
check "--out y --verify juntos -> exit 2" "2" "$?"

# ── 3. Source validation (fail loudly, con la ruta) ──────────────────────────
out="$(run "$TMP/no-such-config.env" "$TMP/src/secrets" --out "$TMP/out" </dev/null 2>&1)"; rc=$?
check "config.env ausente -> exit 1" "1" "$rc"
check_contains "config.env ausente: menciona la ruta" "$out" "$TMP/no-such-config.env"

out="$(run "$TMP/src/config/config.env" "$TMP/no-such-secrets" --out "$TMP/out" </dev/null 2>&1)"; rc=$?
check "secrets/ ausente -> exit 1" "1" "$rc"
check_contains "secrets/ ausente: menciona la ruta" "$out" "$TMP/no-such-secrets"

# ── 4. Passphrase gate (mismo trato que database backup) ─────────────────────
make_sources "CHANGE_ME"
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --out "$TMP/out" </dev/null 2>&1)"; rc=$?
check "CHANGE_ME -> exit 1" "1" "$rc"
check_contains "CHANGE_ME: mensaje claro" "$out" "CHANGE_ME"

mkdir -p "$TMP/src/config2" "$TMP/src/secrets2"
printf 'ConnectionStrings__MariaDB="Server=db;Database=ema;User=u;Password=p;"\n' > "$TMP/src/config2/config.env"
cp "$TMP/src/secrets/rsa-private-key.pem" "$TMP/src/secrets2/"
out="$(run "$TMP/src/config2/config.env" "$TMP/src/secrets2" --out "$TMP/out" </dev/null 2>&1)"; rc=$?
check "sin passphrase -> exit 1" "1" "$rc"
check_contains "sin passphrase: menciona la variable" "$out" "Backup__EncryptionPassphrase"

# ── 5. Destino bajo /app: rechazado (confirm no disponible en test = EOF) ────
make_sources "testpass-DO-NOT-PRINT"
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --out /app/respaldo-secrets-test </dev/null 2>&1)"; rc=$?
check "--out bajo /app sin confirmar -> exit 1" "1" "$rc"
check_contains "--out bajo /app: explica el rechazo" "$out" "/app"
[[ -d /app/respaldo-secrets-test ]] && { printf '  FAIL  --out bajo /app creo el directorio\n'; FAIL=$((FAIL + 1)); } || { printf '  ok    --out bajo /app: no creo nada\n'; PASS=$((PASS + 1)); }

# ── 6. Happy path: artifacto, modo, SHA-256 y comando de restauracion ────────
make_sources "testpass-DO-NOT-PRINT"
OUT="$TMP/out"
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --out "$OUT" </dev/null 2>&1)"; rc=$?
check "backup: exit 0" "0" "$rc"
enc_file="$(find "$OUT" -maxdepth 1 -name 'secrets-backup-*.tar.gz.enc' 2>/dev/null | head -1)"
[[ -n "$enc_file" ]] && { printf '  ok    backup: crea secrets-backup-*.tar.gz.enc\n'; PASS=$((PASS + 1)); } || { printf '  FAIL  backup: no creo el archivo .tar.gz.enc\n'; FAIL=$((FAIL + 1)); }
if [[ -n "$enc_file" ]]; then
  check "backup: archivo modo 600" "600" "$(stat -c '%a' "$enc_file")"
  check "backup: directorio de salida modo 700" "700" "$(stat -c '%a' "$OUT")"
  check_contains "backup: imprime hash sha256sum" "$out" "$(sha256sum "$enc_file" | awk '{print $1}')"
fi
check_contains "backup: imprime SHA-256"        "$out" "SHA-256"
check_contains "backup: comando de restauracion (openssl -d)" "$out" "openssl enc -d -aes-256-cbc -pbkdf2"
check_contains "backup: comando de restauracion (tar -xz -C /)" "$out" "tar -xz -C /"
check_contains "backup: passphrase como placeholder (no el valor)" "$out" "<PASSPHRASE>"
check_contains "backup: aviso off-site (DOC-23)" "$out" "fuera del servidor"
# NUNCA imprimir material sensible:
check_absent "backup: NO imprime la passphrase"     "$out" "testpass-DO-NOT-PRINT"
check_absent "backup: NO imprime el hash key PII"   "$out" "FAKE-HASH-KEY-VALUE"
check_absent "backup: NO imprime la password de BD" "$out" "FAKE-DB-PASS"
check_absent "backup: NO imprime el cuerpo del PEM" "$out" "FAKE-PEM-BODY"

# ── 7. --verify: checksum + prueba de descifrado (solo NOMBRES) ──────────────
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --verify "$enc_file" </dev/null 2>&1)"; rc=$?
check "verify: exit 0" "0" "$rc"
if [[ -n "$enc_file" ]]; then
  check_contains "verify: imprime SHA-256" "$out" "$(sha256sum "$enc_file" | awk '{print $1}')"
fi
check_contains "verify: lista config.env"            "$out" "config.env"
check_contains "verify: lista rsa-private-key.pem"   "$out" "rsa-private-key.pem"
check_absent "verify: NO imprime la passphrase"   "$out" "testpass-DO-NOT-PRINT"
check_absent "verify: NO imprime el hash key PII" "$out" "FAKE-HASH-KEY-VALUE"
check_absent "verify: NO imprime el cuerpo del PEM" "$out" "FAKE-PEM-BODY"
leftover="$(find /tmp -maxdepth 1 -name 'tmp.*' -newer "$BS" -type d 2>/dev/null | wc -l)"
[[ "$leftover" == "0" ]] || { printf '  FAIL  verify: dejo directorios temporales (%s)\n' "$leftover"; FAIL=$((FAIL + 1)); }

# ── 8. --verify: passphrase incorrecta / archivo corrupto ────────────────────
make_sources "OTRA-passphrase"
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --verify "$enc_file" </dev/null 2>&1)"; rc=$?
check "verify con otra passphrase -> exit 1" "1" "$rc"
check_contains "verify con otra passphrase: dice passphrase incorrecta" "$out" "passphrase incorrecta"
check_absent   "verify con otra passphrase: NO dice archivo corrupto" "$out" "archivo corrupto"

# Descifra bien (passphrase CORRECTA) pero el contenido no es un tar.gz:
make_sources "testpass-DO-NOT-PRINT"
printf 'no-es-un-respaldo' > "$TMP/no-tar.txt"
if ! openssl enc -aes-256-cbc -pbkdf2 -salt -pass "pass:testpass-DO-NOT-PRINT" \
       -in "$TMP/no-tar.txt" -out "$TMP/no-tar.enc"; then
  printf '  FAIL  fixture: no se pudo crear no-tar.enc\n'; FAIL=$((FAIL + 1))
fi
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --verify "$TMP/no-tar.enc" </dev/null 2>&1)"; rc=$?
check "verify de contenido no-tar -> exit 1" "1" "$rc"
check_contains "verify no-tar: dice archivo corrupto o vacio" "$out" "archivo corrupto o vacio"
check_absent   "verify no-tar: NO acusa la passphrase" "$out" "passphrase incorrecta"

printf 'no-es-un-respaldo' > "$TMP/basura.enc"
out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --verify "$TMP/basura.enc" </dev/null 2>&1)"; rc=$?
check "verify de archivo corrupto -> exit 1" "1" "$rc"
check_contains "verify de archivo corrupto: avisa fallo de descifrado" "$out" "No se pudo descifrar"

out="$(run "$TMP/src/config/config.env" "$TMP/src/secrets" --verify "$TMP/no-existe.enc" </dev/null 2>&1)"; rc=$?
check "verify de archivo inexistente -> exit 1" "1" "$rc"
check_contains "verify inexistente: menciona la ruta" "$out" "$TMP/no-existe.enc"

# ── 9. --verify sin passphrase: degrada a checksum y lo dice ─────────────────
out="$(run "$TMP/src/config2/config.env" "$TMP/src/secrets2" --verify "$enc_file" </dev/null 2>&1)"; rc=$?
check "verify sin passphrase: exit 0 (limitado)" "0" "$rc"
if [[ -n "$enc_file" ]]; then
  check_contains "verify sin passphrase: imprime SHA-256" "$out" "$(sha256sum "$enc_file" | awk '{print $1}')"
fi
check_contains "verify sin passphrase: avisa que no descifra" "$out" "no se puede probar el descifrado"

# ── 10. Registro: menu system, help de bin/deploy, primitiva compartida ──────
menu_src="$(cat "$ROOT/modules/system/menu.sh")"
check_contains "menu system: entrada backup-secrets"      "$menu_src" "backup-secrets.sh"
deploy_src="$(cat "$ROOT/bin/deploy")"
check_contains "bin/deploy help: lista backup-secrets"    "$deploy_src" "backup-secrets"
modhelp_out="$(bash "$ROOT/bin/deploy" system --help 2>&1)"
check_contains "deploy system --help lista backup-secrets" "$modhelp_out" "backup-secrets"
bs_src="$(cat "$BS")"
check_contains "usa la MISMA primitiva que backup-db.sh (aes-256-cbc -pbkdf2)" "$bs_src" "openssl enc -aes-256-cbc -pbkdf2 -salt"
check_contains "usa Backup__EncryptionPassphrase (no otra clave)" "$bs_src" "Backup__EncryptionPassphrase"

# ── 11. Harness fail-fast: mktemp roto no debe seguir con TMP vacio ──────────
# Si mktemp falla y TMP queda vacio, los fixtures colapsan a / (p.ej. intento
# de escribir /basura.enc). El suite debe abortar de inmediato con un aviso.
stub_dir="$TMP/mktemp-stub"
mkdir -p "$stub_dir"
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub_dir/mktemp"
chmod +x "$stub_dir/mktemp"
harness_out="$(PATH="$stub_dir:$PATH" bash "$SCRIPT_DIR/test-backup-secrets.sh" </dev/null 2>&1)"; harness_rc=$?
check "harness: mktemp roto -> exit 1" "1" "$harness_rc"
check_contains "harness: mktemp roto -> avisa del fallo" "$harness_out" "mktemp"
check_absent   "harness: mktemp roto -> no corre la suite" "$harness_out" "respaldo cifrado de secretos"

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
