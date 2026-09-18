#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/release/commands/build.sh — Build and package a component
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/release-common.sh"

# Raiz del deploy: commands -> release -> modules -> bs_deploy (3 niveles).
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=/dev/null
source "$DEPLOY_ROOT/core/csp.sh"

# Raiz del repo: un nivel MAS arriba que bs_deploy, donde viven frontend/ y
# backend/. Antes esto usaba 3 niveles y caia en bs_deploy/, asi que
# 'cd ${REPO_ROOT}/frontend' apuntaba a un directorio inexistente y el build
# del frontend abortaba por set -e.
REPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"

if [[ ! -d "$REPO_ROOT/frontend" || ! -d "$REPO_ROOT/backend" ]]; then
  err "No encontre frontend/ y backend/ en: $REPO_ROOT"
  err "Este comando se corre desde el repo de desarrollo, no desde el servidor."
  exit 1
fi

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

  # Hash CSP del <style> inline del loader, calculado sobre el BUILD (no sobre
  # el fuente: Vite minifica y normaliza CRLF -> LF, y el hash del fuente no
  # matchea). El server lo recalcula solo en 'frontend install'; esto es para
  # poder verificar que quedo bien sin entrar al servidor.
  if ! CSP_STYLE_HASH="$(compute_csp_style_hash "${dist_dir}/index.html")"; then
    err "No se pudo calcular el hash CSP del loader. No se empaqueta."
    exit 1
  fi
  ok "Hash CSP del loader: sha256-${CSP_STYLE_HASH}"

  GENERATED_RAR="${REPO_ROOT}/app.rar"
  rm -f "$GENERATED_RAR"
  (cd "$dist_dir" && "$RAR_EXE" a -r "$GENERATED_RAR" .)
  ok "app.rar generado: $GENERATED_RAR ($(du -h "$GENERATED_RAR" | cut -f1))"
}

build_backend() {
  local publish_dir="${REPO_ROOT}/backend/publish"
  log "Publicando backend (dotnet publish)..."

  # Publish acotado al server real (Ubuntu 24.04 amd64). Sin estos flags el
  # publish pesaba 166 MB y 295 archivos, de los cuales sobraban:
  #   -r linux-x64 --self-contained false
  #       runtimes/ traia 11 RIDs (osx, win-x86, linux-arm, musl...) = 106 MB
  #       para una maquina que solo es linux-x64. Con RID, las nativas
  #       (libSkiaSharp.so, libQuestPdfSkia.so) se aplanan a la raiz, que es
  #       donde .NET las busca. Ademas genera el apphost ELF de Linux en vez
  #       de Api.exe (un binario de Windows que nunca iba a correr aca).
  #       --self-contained false: el server ya tiene el runtime .NET instalado
  #       por bootstrap.sh, no hace falta embeberlo.
  #   -p:DebugType=none
  #       .pdb son simbolos de depuracion: no se entregan al cliente.
  #   -p:SatelliteResourceLanguages=en
  #       13 carpetas de idioma (cs, de, ja, zh-Hans...) con recursos de
  #       Roslyn y WCF = 12 MB que nadie lee.
  # Resultado: 166 MB -> 64 MB, 295 -> 143 archivos.
  #
  # OJO: el servicio arranca por 'dotnet Api.dll' (setup-server.sh), no por
  # el apphost. Api.dll tiene que seguir estando en el publish.
  dotnet publish "${REPO_ROOT}/backend/Api/Api.csproj" -c Release -o "$publish_dir" --nologo \
    -r linux-x64 --self-contained false \
    -p:DebugType=none \
    -p:SatelliteResourceLanguages=en

  if [[ ! -f "$publish_dir/Api.dll" ]]; then
    err "El publish no genero Api.dll — el servicio no podria arrancar."
    exit 1
  fi
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
if [[ "$COMPONENT" == "frontend" ]]; then
  printf "  Hash CSP   : sha256-%s\n" "$CSP_STYLE_HASH"
fi
divider
echo
log "Copia este archivo al servidor: scp app.rar user@server:/tmp/"
