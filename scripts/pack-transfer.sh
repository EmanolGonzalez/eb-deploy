#!/usr/bin/env bash
# =============================================================================
# scripts/pack-transfer.sh — Genera el paquete de transferencia partido
#
# El toolkit viaja liviano y los assets viajan por componente:
#
#   deploy.rar                    toolkit completo, SIN assets/
#   deploy_<grupo>_assets.rar     assets/<grupo>/ de cada grupo existente
#   deploy_assets_all.rar         todos los assets juntos (--all)
#   SHA256SUMS.txt                checksum SHA-256 de cada parte
#
# Cada .rar de assets guarda las rutas "assets/<grupo>/..." para que al
# extraerlo en la raiz del repo (/app/deploy) quede el mismo arbol que esperan
# bootstrap.sh e instaladores. Ningun .rar lleva carpeta envolvente.
#
# Este script corre en la maquina de build/transferencia, NO en el servidor
# del cliente. Es standalone a proposito: no es un comando del modulo deploy.
#
# Uso: scripts/pack-transfer.sh [--out DIR] [--all | --only GRUPO] [--help]
#
# Crear .rar requiere rar/WinRAR en esta maquina (licencia del proveedor).
# El cliente solo necesita 'unrar', que viaja en assets/tools/ y lo instala
# setup/bootstrap.sh.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# ── Salida (mismo estilo que core/logger.sh, sin depender de core/) ──────────
log()  { echo -e "\033[1;34m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
err()  { echo -e "\033[1;31mERR  $*\033[0m" >&2; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }
step() { echo; echo -e "\033[1;37m--- $* ---\033[0m"; }

usage() {
  cat <<'EOF'
pack-transfer.sh — Genera el paquete de transferencia partido del toolkit

Uso:
  scripts/pack-transfer.sh [opciones]

Opciones:
  --out <dir>     Directorio de salida (default: <repo>/transfer/)
  --all           Genera deploy.rar + deploy_assets_all.rar (todos los assets
                  en un solo archivo)
  --only <grupo>  Genera deploy.rar + deploy_<grupo>_assets.rar (transferencia
                  incremental: solo el grupo que cambio)
  --help, -h      Muestra esta ayuda

Partes:
  deploy.rar                   toolkit completo, sin assets/
  deploy_<grupo>_assets.rar    assets/<grupo>/ (una parte por grupo existente)
  deploy_assets_all.rar        todos los assets juntos (solo con --all)
  SHA256SUMS.txt               checksum SHA-256 de cada parte producida

Extraccion (en la raiz del repo, por ejemplo /app/deploy):
  unrar x deploy.rar
  unrar x deploy_<grupo>_assets.rar
  sha256sum -c SHA256SUMS.txt

rar se busca en este orden: PATH, rutas de WinRAR, assets/tools/rarlinux*.tar.gz.
EOF
}

usage_error() {
  err "$*"
  echo
  usage >&2
  exit 2
}

# ── Argumentos ───────────────────────────────────────────────────────────────
OUT_DIR="$ROOT/transfer"
MODE="groups"
ONLY_GROUP=""
MODE_COUNT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "Falta el valor de --out"
      OUT_DIR="$2"
      shift 2
      ;;
    --all)
      MODE="all"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --only)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "Falta el valor de --only"
      MODE="only"
      ONLY_GROUP="$2"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      usage_error "Opcion desconocida: $1"
      ;;
    *)
      usage_error "Argumento inesperado: $1"
      ;;
  esac
done

if [[ -n "$ONLY_GROUP" && "$MODE" == "all" ]]; then
  usage_error "--all y --only son mutuamente excluyentes"
fi
if [[ "$MODE_COUNT" -gt 1 && "$MODE" == "only" ]]; then
  usage_error "Usa un solo --only (o --all) por ejecucion"
fi

if [[ -n "$ONLY_GROUP" ]]; then
  case "$ONLY_GROUP" in
    */*|.|..)
      usage_error "Grupo invalido para --only: $ONLY_GROUP"
      ;;
  esac
fi

# ── Preparacion del directorio de salida y temporales ───────────────────────
mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd -P)"
if [[ "$OUT_ABS" == "$ROOT" ]]; then
  usage_error "--out no puede ser la raiz del repo (se empaquetaria a si mismo)"
fi

TMP_WORK="$(mktemp -d "$OUT_ABS/.pack-transfer.XXXXXX")"
cleanup() { rm -rf "$TMP_WORK"; }
trap cleanup EXIT
mkdir -p "$TMP_WORK/build"

# Si la salida cae dentro del repo, excluirla del deploy.rar (el default
# transfer/ ya esta excluido siempre).
OUT_REL=""
if [[ "$OUT_ABS" == "$ROOT"/* ]]; then
  OUT_REL="${OUT_ABS#"$ROOT"/}"
fi

# ── Localizar rar ────────────────────────────────────────────────────────────
RAR_EXE=""
RAR_SOURCE=""

find_rar() {
  local candidate tgz
  if command -v rar >/dev/null 2>&1; then
    RAR_EXE="$(command -v rar)"
    RAR_SOURCE="PATH"
    return 0
  fi

  for candidate in \
      "/c/Program Files/WinRAR/rar.exe" \
      "/c/Program Files (x86)/WinRAR/rar.exe"; do
    if [[ -f "$candidate" ]]; then
      RAR_EXE="$candidate"
      RAR_SOURCE="WinRAR ($candidate)"
      return 0
    fi
  done

  for tgz in "$ROOT/assets/tools"/rarlinux*.tar.gz; do
    [[ -f "$tgz" ]] || continue
    mkdir -p "$TMP_WORK/rar-bin"
    if tar -xzf "$tgz" -C "$TMP_WORK/rar-bin" >/dev/null 2>&1; then
      if [[ -f "$TMP_WORK/rar-bin/rar/rar" ]]; then
        chmod +x "$TMP_WORK/rar-bin/rar/rar"
        RAR_EXE="$TMP_WORK/rar-bin/rar/rar"
        RAR_SOURCE="assets/tools/$(basename "$tgz")"
        return 0
      fi
    fi
  done

  return 1
}

if ! find_rar; then
  err "No encontre 'rar'."
  err "Instala WinRAR/rar en esta maquina o deja rarlinux-*.tar.gz en assets/tools/."
  exit 1
fi

log "rar: $RAR_EXE (origen: $RAR_SOURCE)"

# ── Grupos de assets ─────────────────────────────────────────────────────────
ASSETS_DIR="$ROOT/assets"
ASSET_GROUPS=()
if [[ -d "$ASSETS_DIR" ]]; then
  for d in "$ASSETS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    ASSET_GROUPS+=("$(basename "$d")")
  done
fi

if [[ "$MODE" == "only" ]]; then
  if [[ ! -d "$ASSETS_DIR/$ONLY_GROUP" ]]; then
    err "No existe el grupo de assets: assets/$ONLY_GROUP"
    err "Grupos disponibles: ${ASSET_GROUPS[*]:-ninguno}"
    exit 1
  fi
  ASSET_GROUPS=("$ONLY_GROUP")
elif [[ "$MODE" == "all" ]]; then
  if [[ ! -d "$ASSETS_DIR" ]]; then
    err "No existe el directorio assets/ en $ROOT"
    exit 1
  fi
fi

# ── Empaquetado ──────────────────────────────────────────────────────────────
PARTS=()

make_deploy() {
  local tmp="$TMP_WORK/build/deploy.rar"
  local excludes=(-xassets -x.git -xnode_modules -xtransfer)
  if [[ -n "$OUT_REL" && "$OUT_REL" != "transfer" ]]; then
    excludes+=("-x$OUT_REL")
  fi

  log "Generando deploy.rar (toolkit sin assets/)..."
  (
    cd "$ROOT"
    "$RAR_EXE" a -r -idq -y "${excludes[@]}" "$tmp" .
  )
  mv -f "$tmp" "$OUT_ABS/deploy.rar"
  PARTS+=("deploy.rar")
  ok "deploy.rar ($(du -h "$OUT_ABS/deploy.rar" | cut -f1))"
}

make_group() {
  local group="$1"
  local name="deploy_${group}_assets.rar"
  local tmp="$TMP_WORK/build/$name"

  log "Generando $name (assets/$group/)..."
  (
    cd "$ROOT"
    "$RAR_EXE" a -r -idq -y "$tmp" "assets/$group"
  )
  mv -f "$tmp" "$OUT_ABS/$name"
  PARTS+=("$name")
  ok "$name ($(du -h "$OUT_ABS/$name" | cut -f1))"
}

make_all() {
  local name="deploy_assets_all.rar"
  local tmp="$TMP_WORK/build/$name"

  log "Generando $name (todos los assets)..."
  (
    cd "$ROOT"
    "$RAR_EXE" a -r -idq -y "$tmp" assets
  )
  mv -f "$tmp" "$OUT_ABS/$name"
  PARTS+=("$name")
  ok "$name ($(du -h "$OUT_ABS/$name" | cut -f1))"
}

step "Partes"
make_deploy

case "$MODE" in
  all)
    make_all
    ;;
  only)
    make_group "$ONLY_GROUP"
    ;;
  groups)
    if [[ ${#ASSET_GROUPS[@]} -eq 0 ]]; then
      warn "No hay grupos en assets/ (solo se genero deploy.rar)."
    else
      for group in "${ASSET_GROUPS[@]}"; do
        make_group "$group"
      done
    fi
    ;;
esac

# ── Checksums y resumen ──────────────────────────────────────────────────────
(
  cd "$OUT_ABS"
  sha256sum -- "${PARTS[@]}" > SHA256SUMS.txt
)

step "Resumen"
printf '%-36s %10s\n' "PARTE" "TAMANO"
printf '%-36s %10s\n' "------------------------------------" "----------"
total_kb=0
for part in "${PARTS[@]}"; do
  printf '%-36s %10s\n' "$part" "$(du -h "$OUT_ABS/$part" | cut -f1)"
  kb="$(du -k "$OUT_ABS/$part" | cut -f1)"
  total_kb=$((total_kb + kb))
done
printf '%-36s %10s\n' "------------------------------------" "----------"
printf '%-36s %10s\n' "TOTAL" "$(numfmt --to=iec --suffix=B $((total_kb * 1024)) 2>/dev/null || echo "${total_kb}K")"
printf '%-36s %10s\n' "SHA256SUMS.txt" "$(du -h "$OUT_ABS/SHA256SUMS.txt" | cut -f1)"

echo
ok "Paquete listo en: $OUT_ABS"
info_cmd="cd \"$OUT_ABS\" && sha256sum -c SHA256SUMS.txt"
echo -e "\033[1;34m==>\033[0m Verificar integridad: $info_cmd"
