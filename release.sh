#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# release.sh — Sube un nuevo artifact a Azure Blob Storage
# Versión Git Bash / Windows — usa curl + Azure Blob REST API (sin azcopy)
#
# Uso:
#   bash release.sh
#
# Opcional — evita que el SAS token aparezca en el historial de terminal:
#   AZURE_SAS_TOKEN="sv=..." bash release.sh
#
# Prerequisitos:
#   - curl en PATH (viene incluido con Git for Windows)
#   - bash 4.0+ (Git for Windows incluye bash 4.4+)
#
# Estructura de blobs en Azure:
#   <COMPONENT>/<VERSION>/app.rar
#   Ejemplo: frontend/1.0.0/app.rar | backend/2.3.1/app.rar
# =============================================================================

AZURE_API_VERSION="2020-08-04"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_RAR=""   # Ruta al app.rar generado localmente (se limpia al finalizar)

# ── COLORES / LOGGING ──────────────────────────────────────────────────────────

log()  { echo -e "\033[1;34m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
err()  { echo -e "\033[1;31mERR  $*\033[0m" >&2; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }
step() { echo; echo -e "\033[1;37m--- $* ---\033[0m"; }

# ── FUNCIONES CORE ─────────────────────────────────────────────────────────────

validate_curl() {
  step "Validando dependencias"

  if ! command -v curl &>/dev/null; then
    err "curl no está disponible en PATH."
    err "Git for Windows incluye curl — verifica tu instalación."
    exit 1
  fi

  local curl_version
  curl_version="$(curl --version 2>/dev/null | head -1)"
  ok "curl disponible: $curl_version"
}

load_config() {
  step "Configuración de Azure Storage"

  # STORAGE_ACCOUNT
  read -rp "Cuenta de Azure Storage: " STORAGE_ACCOUNT
  if [[ -z "$STORAGE_ACCOUNT" ]]; then
    err "La cuenta de Azure Storage es obligatoria."
    exit 1
  fi

  # CONTAINER_NAME
  read -rp "Nombre del contenedor: " CONTAINER_NAME
  if [[ -z "$CONTAINER_NAME" ]]; then
    err "El nombre del contenedor es obligatorio."
    exit 1
  fi

  # BASE_URL siempre se deriva de lo ingresado
  BASE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}"

  ok "Cuenta: ${STORAGE_ACCOUNT} | Contenedor: ${CONTAINER_NAME}"
}

request_sas() {
  step "Token SAS de Azure"

  if [[ -n "${AZURE_SAS_TOKEN:-}" ]]; then
    SAS_TOKEN="${AZURE_SAS_TOKEN#\?}"
    log "SAS token cargado desde variable de entorno (${#SAS_TOKEN} chars, ...${SAS_TOKEN: -6})"
    return
  fi

  read -rsp "Introduce el SAS token de Azure (input oculto): " SAS_TOKEN
  echo

  if [[ -z "$SAS_TOKEN" ]]; then
    err "El SAS token es obligatorio."
    exit 1
  fi

  SAS_TOKEN="${SAS_TOKEN#\?}"

  if [[ ${#SAS_TOKEN} -lt 20 ]]; then
    err "El SAS token parece inválido (muy corto: ${#SAS_TOKEN} chars)."
    exit 1
  fi

  log "SAS token recibido: ${#SAS_TOKEN} caracteres (...${SAS_TOKEN: -6})"
}

select_project() {
  step "Selección de componente"

  echo "  1) frontend"
  echo "  2) backend"
  echo

  while true; do
    read -rp "Componente a publicar [1/2]: " idx
    case "$idx" in
      1) COMPONENT="frontend"; break ;;
      2) COMPONENT="backend";  break ;;
      *) warn "Introduce 1 (frontend) o 2 (backend)." ;;
    esac
  done

  ok "Componente seleccionado: $COMPONENT"
}

get_latest_version() {
  step "Detectando versiones existentes en Azure"

  # REST API: List Blobs con prefix para filtrar por componente
  # GET https://<account>.blob.core.windows.net/<container>?restype=container&comp=list&prefix=<component>/
  local list_url="${BASE_URL}?restype=container&comp=list&prefix=${COMPONENT}/&${SAS_TOKEN}"

  log "Consultando Azure Blob Storage REST API..."

  local tmp_response http_code
  tmp_response="$(mktemp)"

  http_code=$(curl -s \
    -H "x-ms-version: ${AZURE_API_VERSION}" \
    -w "%{http_code}" \
    -o "$tmp_response" \
    "$list_url")

  if [[ "$http_code" != "200" ]]; then
    local error_body
    error_body="$(cat "$tmp_response")"
    rm -f "$tmp_response"
    err "Error al listar blobs (HTTP $http_code):"
    err "$error_body"
    err ""
    err "Verifica:"
    err "  1) El SAS token tiene permisos de Read + List"
    err "  2) La cuenta '${STORAGE_ACCOUNT}' y contenedor '${CONTAINER_NAME}' existen"
    err "  3) El SAS token no ha expirado"
    exit 1
  fi

  local response
  response="$(cat "$tmp_response")"
  rm -f "$tmp_response"

  # El XML de respuesta contiene entradas como:
  #   <Name>frontend/1.0.0/app.rar</Name>
  # Extraemos la parte de versión entre <COMPONENT>/ y /app.rar
  mapfile -t ALL_VERSIONS < <(
    echo "$response" \
      | grep -oE "<Name>[^<]+</Name>" \
      | sed 's|<Name>||;s|</Name>||' \
      | grep -E "^${COMPONENT}/[0-9]+\.[0-9]+\.[0-9]+/app\.rar$" \
      | sed -E "s|^${COMPONENT}/||;s|/app\.rar$||" \
      | sort -Vu \
    || true
  )

  if [[ ${#ALL_VERSIONS[@]} -eq 0 ]]; then
    LATEST_VERSION=""
    warn "No se encontraron versiones previas para '${COMPONENT}'."
    warn "La primera release será la versión 1.0.0."
  else
    LATEST_VERSION="${ALL_VERSIONS[-1]}"
    ok "Versiones encontradas: ${ALL_VERSIONS[*]}"
    ok "Versión más reciente: $LATEST_VERSION"
  fi
}

increment_version() {
  local base_version="${1:-0.0.0}"

  if [[ ! "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    err "Versión con formato inesperado: '$base_version'"
    err "Se esperaba X.Y.Z (semver). Ajusta manualmente si es necesario."
    exit 1
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<< "$base_version"
  patch=$(( patch + 1 ))
  NEXT_VERSION="${major}.${minor}.${patch}"
}

validate_local_file() {
  step "Validación del archivo local"

  echo
  read -rp "Ruta al archivo app.rar: " LOCAL_FILE

  # Quitar comillas si el usuario las incluyó (arrastrar-y-soltar en Git Bash)
  LOCAL_FILE="${LOCAL_FILE//\"/}"

  if [[ -z "$LOCAL_FILE" ]]; then
    err "La ruta del archivo es obligatoria."
    exit 1
  fi

  if [[ ! -f "$LOCAL_FILE" ]]; then
    err "Archivo no encontrado: $LOCAL_FILE"
    exit 1
  fi

  local filename
  filename="$(basename "$LOCAL_FILE")"

  if [[ "$filename" != "app.rar" ]]; then
    err "El archivo debe llamarse exactamente 'app.rar'."
    err "Nombre detectado: '$filename'"
    err "Renómbralo antes de subir."
    exit 1
  fi

  local filesize
  filesize="$(du -h "$LOCAL_FILE" | cut -f1)"
  ok "Archivo validado: $LOCAL_FILE ($filesize)"
}

find_rar_executable() {
  if command -v rar &>/dev/null; then
    RAR_EXE="rar"
    ok "WinRAR (rar) encontrado en PATH."
    return
  fi

  local candidates=(
    "/c/Program Files/WinRAR/rar.exe"
    "/c/Program Files (x86)/WinRAR/rar.exe"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      RAR_EXE="$candidate"
      ok "WinRAR encontrado: $RAR_EXE"
      return
    fi
  done

  err "rar.exe no encontrado."
  err "Instala WinRAR y verifica que esté en PATH o en 'C:\\Program Files\\WinRAR\\'."
  exit 1
}

build_frontend() {
  local dist_dir="${REPO_ROOT}/frontend/dist"

  log "Compilando frontend (npm run build)..."
  if ! (cd "${REPO_ROOT}/frontend" && npm run build); then
    err "La compilación del frontend falló."
    exit 1
  fi

  if [[ ! -d "$dist_dir" ]]; then
    err "Directorio dist no encontrado tras el build: $dist_dir"
    exit 1
  fi
  ok "Frontend compilado: $dist_dir"

  log "Empaquetando frontend en app.rar..."
  GENERATED_RAR="${REPO_ROOT}/app.rar"
  rm -f "$GENERATED_RAR"

  # Entramos en dist/ para que los archivos queden en la raíz del RAR
  # (sin prefijo dist/), tal como espera el servidor al extraer con unrar x
  (cd "$dist_dir" && "$RAR_EXE" a -r "$GENERATED_RAR" .)

  ok "app.rar generado: $GENERATED_RAR ($(du -h "$GENERATED_RAR" | cut -f1))"
}

build_backend() {
  local publish_dir="${REPO_ROOT}/backend/publish"

  log "Publicando backend (dotnet publish)..."
  if ! dotnet publish "${REPO_ROOT}/backend/Api/Api.csproj" \
      -c Release \
      -o "$publish_dir" \
      --nologo; then
    err "La publicación del backend falló."
    exit 1
  fi

  if [[ ! -d "$publish_dir" ]]; then
    err "Directorio publish no encontrado: $publish_dir"
    exit 1
  fi
  ok "Backend publicado: $publish_dir"

  log "Empaquetando backend en app.rar..."
  GENERATED_RAR="${REPO_ROOT}/app.rar"
  rm -f "$GENERATED_RAR"

  # Entramos en publish/ para que los archivos queden en la raíz del RAR,
  # igual que el frontend. El servidor accede a ${RELEASE_DIR}/Api.dll directamente.
  (cd "$publish_dir" && "$RAR_EXE" a -r "$GENERATED_RAR" .)

  ok "app.rar generado: $GENERATED_RAR ($(du -h "$GENERATED_RAR" | cut -f1))"
}

offer_build_or_provide() {
  step "Origen del artifact"

  echo "  1) Construir y empaquetar localmente (build automático)"
  echo "  2) Usar un app.rar ya construido (ruta manual)"
  echo

  while true; do
    read -rp "Opción [1/2]: " opt
    case "$opt" in
      1)
        find_rar_executable
        if [[ "$COMPONENT" == "frontend" ]]; then
          build_frontend
        else
          build_backend
        fi
        LOCAL_FILE="$GENERATED_RAR"
        return
        ;;
      2)
        validate_local_file
        return
        ;;
      *)
        warn "Introduce 1 (build automático) o 2 (ruta manual)."
        ;;
    esac
  done
}

check_blob_exists() {
  # Devuelve 0 (true) si el blob ya existe, 1 (false) si no existe.
  local blob_path="$1"
  local url="${BASE_URL}/${blob_path}?${SAS_TOKEN}"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X HEAD \
    -H "x-ms-version: ${AZURE_API_VERSION}" \
    "$url")

  [[ "$http_code" == "200" ]]
}

upload_release() {
  step "Subiendo release a Azure"

  local blob_path="${COMPONENT}/${NEXT_VERSION}/app.rar"
  local upload_url="${BASE_URL}/${blob_path}?${SAS_TOKEN}"

  log "Origen  : $LOCAL_FILE"
  log "Destino : ${blob_path}"
  log "Cuenta  : ${STORAGE_ACCOUNT} / ${CONTAINER_NAME}"

  # Verificar si ya existe esa versión antes de subir
  log "Verificando existencia previa del blob..."
  if check_blob_exists "$blob_path"; then
    err "La versión ${NEXT_VERSION} ya existe en Azure (${blob_path})."
    err "Aborta para evitar sobreescritura accidental."
    exit 1
  fi

  log "Blob no existe — procediendo con la subida..."
  echo

  local tmp_response http_code
  tmp_response="$(mktemp)"

  # PUT blob — REST API de Azure Blob Storage
  # --upload-file hace streaming del archivo (no carga todo en memoria)
  # --progress-bar muestra progreso en stderr
  http_code=$(curl \
    --progress-bar \
    -X PUT \
    -H "x-ms-version: ${AZURE_API_VERSION}" \
    -H "x-ms-blob-type: BlockBlob" \
    -H "Content-Type: application/octet-stream" \
    --upload-file "$LOCAL_FILE" \
    -w "%{http_code}" \
    -o "$tmp_response" \
    "$upload_url")

  echo  # salto de línea tras la barra de progreso

  local response_body
  response_body="$(cat "$tmp_response")"
  rm -f "$tmp_response"

  # Azure devuelve 201 Created en subida exitosa
  if [[ "$http_code" != "201" ]]; then
    err "La subida falló (HTTP $http_code)."
    if [[ -n "$response_body" ]]; then
      err "Respuesta de Azure:"
      err "$response_body"
    fi
    err ""
    err "Causas posibles:"
    err "  1) El SAS token no tiene permiso de Write / Create"
    err "  2) El SAS token expiró"
    err "  3) Problema de red o archivo demasiado grande para un solo PUT"
    exit 1
  fi

  ok "Release subida exitosamente: ${blob_path}"
}

# ── MAIN ───────────────────────────────────────────────────────────────────────

validate_curl
load_config
request_sas
select_project
get_latest_version
increment_version "${LATEST_VERSION:-0.0.0}"
offer_build_or_provide

# Resumen antes de confirmar
echo
echo "========================================"
echo "  RESUMEN DE RELEASE"
echo "========================================"
printf "  Componente : %s\n"  "$COMPONENT"
printf "  Versión    : %s\n"  "$NEXT_VERSION"
if [[ -n "${LATEST_VERSION:-}" ]]; then
  printf "  Anterior   : %s\n"  "$LATEST_VERSION"
else
  printf "  Anterior   : (ninguna — primera release)\n"
fi
printf "  Archivo    : %s\n"  "$LOCAL_FILE"
printf "  Blob path  : %s/%s/app.rar\n" "$COMPONENT" "$NEXT_VERSION"
printf "  Contenedor : %s\n"  "$CONTAINER_NAME"
echo "========================================"
echo

read -rp "¿Confirmar release? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  log "Release cancelada por el usuario."
  exit 0
fi

upload_release

# Eliminar app.rar generado automáticamente (no es necesario conservarlo)
if [[ -n "${GENERATED_RAR:-}" && -f "${GENERATED_RAR}" ]]; then
  rm -f "${GENERATED_RAR}"
  log "app.rar temporal eliminado."
fi

echo
log "Release ${COMPONENT} v${NEXT_VERSION} completada exitosamente."
log "Ejecuta el update desde ops-menu.sh en el servidor para deployar esta versión."
