#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/release/commands/build.sh — Build and package a component
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/release-common.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

find_rar() {
  if command -v rar &>/dev/null; then
    RAR_EXE="rar"
    return
  fi
  for candidate in "/c/Program Files/WinRAR/rar.exe" "/c/Program Files (x86)/WinRAR/rar.exe"; do
    if [[ -f "$candidate" ]]; then
      RAR_EXE="$candidate"
      return
    fi
  done
  err "rar.exe no encontrado. Instala WinRAR."
  exit 1
}

build_frontend() {
  local dist_dir="${REPO_ROOT}/frontend/dist"
  log "Compilando frontend (npm run build)..."
  (cd "${REPO_ROOT}/frontend" && npm run build)
  ok "Frontend compilado."

  GENERATED_RAR="${REPO_ROOT}/app.rar"
  rm -f "$GENERATED_RAR"
  (cd "$dist_dir" && "$RAR_EXE" a -r "$GENERATED_RAR" .)
  ok "app.rar generado: $GENERATED_RAR ($(du -h "$GENERATED_RAR" | cut -f1))"
}

build_backend() {
  local publish_dir="${REPO_ROOT}/backend/publish"
  log "Publicando backend (dotnet publish)..."
  dotnet publish "${REPO_ROOT}/backend/Api/Api.csproj" -c Release -o "$publish_dir" --nologo
  ok "Backend publicado."

  GENERATED_RAR="${REPO_ROOT}/app.rar"
  rm -f "$GENERATED_RAR"
  (cd "$publish_dir" && "$RAR_EXE" a -r "$GENERATED_RAR" .)
  ok "app.rar generado: $GENERATED_RAR ($(du -h "$GENERATED_RAR" | cut -f1))"
}

find_rar

menu_select "Componente:" "frontend" "backend"
COMPONENT="$MENU_SELECTION"

read -rp "Version (X.Y.Z): " VERSION
if ! is_semver "$VERSION"; then
  err "Version invalida. Usa formato semver X.Y.Z"
  exit 1
fi

# Gate: lint de scripts ANTES de empaquetar. Un script con 'local' suelto,
# sintaxis rota o conexion a BD sin trust SSL no debe llegar al server.
LINT_SCRIPT="$(cd "$SCRIPT_DIR/../.." && pwd)/system/commands/lint.sh"
if [[ -f "$LINT_SCRIPT" ]]; then
  log "Verificando scripts (lint) antes de empaquetar..."
  if ! bash "$LINT_SCRIPT"; then
    err "Lint fallo. No se empaqueta hasta corregir los scripts."
    exit 1
  fi
fi

if [[ "$COMPONENT" == "frontend" ]]; then
  build_frontend
else
  build_backend
fi

echo
divider
echo "  BUILD COMPLETADO"
divider
printf "  Componente : %s\n" "$COMPONENT"
printf "  Version    : %s\n" "$VERSION"
printf "  Archivo    : %s\n" "$GENERATED_RAR"
divider
echo
log "Copia este archivo al servidor: scp app.rar user@server:/tmp/"
