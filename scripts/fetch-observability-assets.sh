#!/usr/bin/env bash
# =============================================================================
# scripts/fetch-observability-assets.sh
#
# Populate assets/observability/ for the air-gapped server, downloading the
# exact versions pinned by ADR-007 from the official channels and verifying
# their SHA-256 checksums. Run this on a machine WITH Internet, then copy
# assets/observability/ to the server (like the other binary assets; the
# folder is gitignored because it carries large binaries).
#
# Usage: scripts/fetch-observability-assets.sh [--out DIR]
#
# Versions/checksums are read from modules/observability/manifest.json via the
# module's own library (single source of truth), so this script cannot drift
# from what the installer expects.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$BASE_DIR/modules/observability/lib/observability-common.sh"

OUT_DIR="${OBS_ASSETS_DIR}"
mkdir -p "$OUT_DIR"

log()  { echo -e "\033[1;34m==>\033[0m $*"; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }
err()  { echo -e "\033[1;31mERR  $*\033[0m" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift ;;
    *) err "Opcion desconocida: $1"; exit 1 ;;
  esac
  shift
done

if ! command -v curl >/dev/null 2>&1; then
  err "curl es necesario para descargar los assets."
  exit 1
fi

log "Destino de assets: $OUT_DIR"
echo

for c in "${OBS_COMPONENTS[@]}"; do
  file="$(obs_field "$c" FILE)"
  url="$(obs_field "$c" URL)"
  sha="$(obs_field "$c" SHA256)"
  ver="$(obs_field "$c" VERSION)"
  dest="$OUT_DIR/$file"

  if [[ -f "$dest" ]] && [[ "$(sha256_of "$dest")" == "$sha" ]]; then
    ok "$c v$ver ya presente y verificado."
    continue
  fi

  log "Descargando $c v$ver..."
  echo "    $url"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$dest.part" "$url"
  actual="$(sha256_of "$dest.part")"
  if [[ "$actual" != "$sha" ]]; then
    err "$c: checksum NO coincide."
    err "  Esperado: $sha"
    err "  Obtenido: $actual"
    rm -f "$dest.part"
    exit 1
  fi
  mv "$dest.part" "$dest"
  ok "$c v$ver verificado ($actual)."
done

# Record the exact resolved versions/checksums next to the binaries.
cat > "$OUT_DIR/VERSIONS.txt" <<EOF
# Observabilidad — assets offline (ADR-007). Generado $(date -u '+%Y-%m-%dT%H:%M:%SZ').
EOF
for c in "${OBS_COMPONENTS[@]}"; do
  printf '%-12s %-10s %s  %s\n' "$c" "$(obs_field "$c" VERSION)" "$(obs_field "$c" SHA256)" "$(obs_field "$c" FILE)" >> "$OUT_DIR/VERSIONS.txt"
done

echo
ok "Assets listos en $OUT_DIR"
cat "$OUT_DIR/VERSIONS.txt"
