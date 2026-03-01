#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# release.sh — Sube un nuevo artifact a Azure Blob Storage
#
# Uso:
#   bash release.sh
#   AZURE_SAS_TOKEN="sv=..." bash release.sh
#
# Prerequisitos:
#   - azcopy instalado y en PATH
#   - /app/config/config.env con STORAGE_ACCOUNT, CONTAINER_NAME, BASE_URL
#   - El archivo local debe llamarse exactamente app.rar
#
# Estructura de blobs en Azure:
#   <COMPONENT>/<VERSION>/app.rar
#   Ejemplo: frontend/1.0.0/app.rar | backend/2.3.1/app.rar
# =============================================================================

CONFIG_FILE="/app/config/config.env"

# ----------------------------- COLORES / LOGGING -----------------------------

log()  { echo -e "\033[1;34m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
err()  { echo -e "\033[1;31mERR  $*\033[0m" >&2; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }
step() { echo; echo -e "\033[1;37m--- $* ---\033[0m"; }

# ----------------------------- FUNCIONES CORE --------------------------------

load_config() {
  step "Cargando configuración"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "No se encontró el archivo de configuración: $CONFIG_FILE"
    err "Ejecuta setup-server.sh primero, o crea $CONFIG_FILE manualmente."
    err ""
    err "Formato requerido:"
    err "  STORAGE_ACCOUNT=\"mi-cuenta\""
    err "  CONTAINER_NAME=\"mi-contenedor\""
    err "  BASE_URL=\"https://mi-cuenta.blob.core.windows.net/mi-contenedor\""
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$CONFIG_FILE"

  local required=(STORAGE_ACCOUNT CONTAINER_NAME BASE_URL)
  local missing=()
  for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Variables requeridas no definidas en $CONFIG_FILE:"
    for var in "${missing[@]}"; do
      err "  - $var"
    done
    exit 1
  fi

  # Quitar trailing slash de BASE_URL si lo tiene
  BASE_URL="${BASE_URL%/}"

  ok "Config: cuenta=${STORAGE_ACCOUNT} | contenedor=${CONTAINER_NAME}"
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

  # Normalizar: quitar '?' inicial si está presente
  SAS_TOKEN="${SAS_TOKEN#\?}"

  if [[ ${#SAS_TOKEN} -lt 20 ]]; then
    err "El SAS token parece inválido (muy corto: ${#SAS_TOKEN} chars)."
    exit 1
  fi

  log "SAS token recibido: ${#SAS_TOKEN} caracteres (...${SAS_TOKEN: -6})"
}

validate_azcopy() {
  step "Validando azcopy"

  if ! command -v azcopy &>/dev/null; then
    err "azcopy no está instalado o no está en PATH."
    err ""
    err "Opciones de instalación:"
    err "  1) Ejecuta setup-server.sh (instala azcopy automáticamente)"
    err "  2) Descarga manual desde: https://aka.ms/downloadazcopy-v10-linux"
    err "     tar -xzf azcopy.tar.gz && mv azcopy*/azcopy /usr/local/bin/ && chmod +x /usr/local/bin/azcopy"
    exit 1
  fi

  local azcopy_version
  azcopy_version="$(azcopy --version 2>/dev/null | head -1 || echo "desconocida")"
  ok "azcopy disponible: $azcopy_version"
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

  local container_sas_url="${BASE_URL}?${SAS_TOKEN}"

  log "Consultando Azure Blob Storage..."

  local list_output
  if ! list_output=$(azcopy list "$container_sas_url" 2>&1); then
    # Si el contenedor está vacío, azcopy puede retornar error o vacío
    if echo "$list_output" | grep -qi "no blobs\|BlobNotFound\|ContainerNotFound"; then
      LATEST_VERSION=""
      warn "El contenedor está vacío o no contiene releases del componente $COMPONENT."
      return
    fi
    err "Error al consultar Azure:"
    err "$list_output"
    err ""
    err "Verifica:"
    err "  1) El SAS token tiene permisos de Read + List"
    err "  2) La cuenta '$STORAGE_ACCOUNT' y contenedor '$CONTAINER_NAME' existen"
    err "  3) El SAS token no ha expirado"
    exit 1
  fi

  # Extraer versiones del componente desde output de azcopy list
  # Formato de línea: "INFO: frontend/1.0.0/app.rar; Last Modified: ..."
  # Extraemos el segmento VERSION entre <COMPONENT>/ y /app.rar
  mapfile -t ALL_VERSIONS < <(
    echo "$list_output" \
      | grep -oE "${COMPONENT}/[0-9]+\.[0-9]+\.[0-9]+/app\.rar" \
      | sed -E "s|^${COMPONENT}/||;s|/app\.rar$||" \
      | sort -Vu
  )

  if [[ ${#ALL_VERSIONS[@]} -eq 0 ]]; then
    LATEST_VERSION=""
    warn "No se encontraron versiones previas para '$COMPONENT'."
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
  read -rp "Ruta local al archivo app.rar: " LOCAL_FILE

  LOCAL_FILE="${LOCAL_FILE//\"/}"   # quitar comillas si el usuario las incluyó
  LOCAL_FILE="${LOCAL_FILE// /\ }"  # escapar espacios (defensivo)

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

upload_release() {
  step "Subiendo release a Azure"

  local blob_path="${COMPONENT}/${NEXT_VERSION}/app.rar"
  local dest_url="${BASE_URL}/${blob_path}?${SAS_TOKEN}"

  log "Origen  : $LOCAL_FILE"
  log "Destino : ${COMPONENT}/${NEXT_VERSION}/app.rar"
  log "Cuenta  : ${STORAGE_ACCOUNT} / ${CONTAINER_NAME}"

  # --overwrite=false: falla si ya existe esa versión (seguridad)
  if ! azcopy copy "$LOCAL_FILE" "$dest_url" \
      --overwrite=false \
      --put-md5 \
      --log-level=ERROR; then
    err "La subida falló."
    err ""
    err "Causas posibles:"
    err "  1) La versión $NEXT_VERSION ya existe (usa --overwrite=true solo si es intencional)"
    err "  2) El SAS token no tiene permiso de Write"
    err "  3) Problema de red"
    exit 1
  fi

  ok "Release subida exitosamente: ${COMPONENT}/${NEXT_VERSION}/app.rar"
}

# ----------------------------- MAIN ------------------------------------------

validate_azcopy
load_config
request_sas
select_project
get_latest_version
increment_version "${LATEST_VERSION:-0.0.0}"
validate_local_file

# Resumen antes de confirmar
echo
echo "========================================"
echo "  RESUMEN DE RELEASE"
echo "========================================"
printf "  Componente : %s\n"  "$COMPONENT"
printf "  Versión    : %s\n"  "$NEXT_VERSION"
if [[ -n "$LATEST_VERSION" ]]; then
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

echo
log "Release $COMPONENT v${NEXT_VERSION} completada exitosamente."
log "Ahora puedes ejecutar 'Update' desde ops-menu.sh para deployar esta versión."
