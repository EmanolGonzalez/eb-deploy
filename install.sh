#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# install.sh — Instalación de componente desde Azure Blob Storage
# Soporta frontend/backend, listado dinámico de versiones con azcopy,
# manejo seguro del SAS token, y cadena de conexión de BD.
# =============================================================================

CONFIG_FILE="/app/config/config.env"
INSTALL_BASE="/app"

# ----------------------------- UTILIDADES ------------------------------------

log()  { echo -e "\033[1;34m==> $*\033[0m"; }
err()  { echo -e "\033[1;31mError: $*\033[0m" >&2; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }

arrow_select() {
  local prompt="$1"; shift
  local options=("$@")
  local num=${#options[@]}
  local idx
  echo
  echo "$prompt"
  echo "Escribe el número de la opción y presiona Enter:"
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}"
  done
  while true; do
    read -rp "Opción: " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= num )); then
      ARROW_SELECTION="${options[$((idx-1))]}"
      return
    fi
    err "Opción inválida. Introduce un número entre 1 y $num."
  done
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}

# ----------------------------- CONFIG ----------------------------------------

# Actualiza una clave en config.env preservando el resto del archivo.
# Maneja caracteres especiales en el valor (backslashes, comillas).
update_config_value() {
  local key="$1" value="$2"
  local safe="${value//\\/\\\\}"; safe="${safe//\"/\\\"}"
  local tmp found=false
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^"${key}=" ]]; then
      printf '%s="%s"\n' "$key" "$safe" >> "$tmp"
      found=true
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$CONFIG_FILE"
  [[ "$found" == false ]] && printf '\n%s="%s"\n' "$key" "$safe" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

load_config() {
  local require_storage="${1:-true}"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "Archivo de configuración no encontrado: $CONFIG_FILE"
    err "Ejecuta setup-server.sh para inicializar la configuración."
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"

  if [[ "$require_storage" == "true" ]]; then
    local required=(STORAGE_ACCOUNT CONTAINER_NAME BASE_URL)
    local missing=()
    for var in "${required[@]}"; do
      [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
      err "Variables requeridas no definidas en $CONFIG_FILE:"
      for var in "${missing[@]}"; do
        err "  - $var"
      done
      exit 1
    fi
  fi

  BASE_URL="${BASE_URL:-}"
  BASE_URL="${BASE_URL%/}"
}

# ----------------------------- AZCOPY ----------------------------------------

validate_azcopy() {
  if ! command -v azcopy &>/dev/null; then
    err "azcopy no está instalado o no está en PATH."
    err "Ejecuta setup-server.sh para instalarlo automáticamente."
    exit 1
  fi
}

validate_download_client() {
  if command -v curl &>/dev/null; then
    DOWNLOAD_CLIENT="curl"
    return
  fi
  if command -v wget &>/dev/null; then
    DOWNLOAD_CLIENT="wget"
    return
  fi

  err "No se encontró cliente de descarga (curl o wget)."
  err "Instala curl o wget para usar instalación por URL directa."
  exit 1
}

# ----------------------------- SAS TOKEN -------------------------------------

request_sas() {
  if [[ -n "${AZURE_SAS_TOKEN:-}" ]]; then
    SAS_TOKEN="${AZURE_SAS_TOKEN#\?}"
    log "SAS token desde variable de entorno (...${SAS_TOKEN: -6})"
    return
  fi
  read -rsp "Azure SAS token (input oculto): " SAS_TOKEN
  echo
  if [[ -z "$SAS_TOKEN" ]]; then
    err "SAS token obligatorio."
    exit 1
  fi
  SAS_TOKEN="${SAS_TOKEN#\?}"
  log "SAS token recibido: ${#SAS_TOKEN} chars (...${SAS_TOKEN: -6})"
}

# ----------------------------- BASE DE DATOS ---------------------------------

load_db_connection_if_exists() {
  # DB_CONNECTION_STRING ya está cargada por load_config() si está en config.env
  if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
    log "Cadena de conexión cargada desde $CONFIG_FILE"
  fi
}

save_db_connection_string() {
  local value="$1"
  update_config_value "DB_CONNECTION_STRING" "$value"
  DB_CONNECTION_STRING="$value"
  ok "DB_CONNECTION_STRING guardada en $CONFIG_FILE"
}

prompt_new_db_connection_string() {
  local value
  read -rsp "ConnectionStrings:DefaultConnection: " value
  echo
  if [[ -z "$value" ]]; then
    err "La cadena de conexión no puede estar vacía."
    exit 1
  fi
  save_db_connection_string "$value"
}

connection_summary() {
  local cs="$1"
  local server database user
  server="$(echo "$cs"   | sed -nE 's/.*[Ss]erver=([^;]+).*/\1/p')"
  database="$(echo "$cs" | sed -nE 's/.*([Dd]atabase|[Ii]nitial [Cc]atalog)=([^;]+).*/\2/p')"
  user="$(echo "$cs"     | sed -nE 's/.*([Uu]ser [Ii][Dd]|[Uu]id)=([^;]+).*/\2/p')"
  [[ -z "$server"   ]] && server="(desconocido)"
  [[ -z "$database" ]] && database="(desconocida)"
  [[ -z "$user"     ]] && user="(integrated/no user)"
  printf 'server=%s | db=%s | user=%s' "$server" "$database" "$user"
}

ensure_db_connection_for_backend() {
  [[ "$COMPONENT" != "backend" ]] && return

  if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
    log "Cadena de conexión actual: $(connection_summary "$DB_CONNECTION_STRING")"
    arrow_select "¿Qué deseas hacer con la cadena de conexión?" \
      "Usar cadena guardada" "Ingresar otra"
    if [[ "$ARROW_SELECTION" == "Ingresar otra" ]]; then
      prompt_new_db_connection_string
    fi
    return
  fi

  arrow_select "No hay cadena de conexión guardada para backend." \
    "Ingresar ahora" "Continuar sin definir"
  if [[ "$ARROW_SELECTION" == "Ingresar ahora" ]]; then
    prompt_new_db_connection_string
  fi
}

escape_for_sed_replacement() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//&/\\&}"
  printf '%s' "$input"
}

apply_connection_string_to_file() {
  local target_file="$1"
  local connection_string="$2"

  if [[ ! -f "$target_file" ]]; then
    err "Archivo no encontrado: $target_file"
    exit 1
  fi
  if ! grep -q '"DefaultConnection"' "$target_file"; then
    err "Clave DefaultConnection no encontrada en: $target_file"
    exit 1
  fi
  local escaped
  escaped="$(escape_for_sed_replacement "$connection_string")"
  sed -i -E "s#(\"DefaultConnection\"[[:space:]]*:[[:space:]]*\").*(\")#\\1${escaped}\\2#" "$target_file"
  ok "Cadena de conexión aplicada a $target_file"
}

# ----------------------------- COMPONENTE ------------------------------------

select_component() {
  arrow_select "Selecciona el componente a instalar:" frontend backend
  COMPONENT="$ARROW_SELECTION"
}

select_install_source() {
  arrow_select "Selecciona el origen del artefacto:" \
    "Cloud (Azure Blob + SAS)" \
    "URL o archivo .rar en servidor"

  case "$ARROW_SELECTION" in
    "Cloud (Azure Blob + SAS)")
      SOURCE_MODE="cloud"
      ;;
    "URL o archivo .rar en servidor")
      SOURCE_MODE="manual"
      ;;
    *)
      err "Origen no soportado: $ARROW_SELECTION"
      exit 1
      ;;
  esac
}

prompt_manual_artifact_source() {
  read -rp "Ruta local o URL de app.rar: " ARTIFACT_SOURCE
  if [[ -z "$ARTIFACT_SOURCE" ]]; then
    err "Debes indicar una ruta local o URL."
    exit 1
  fi
}

prompt_manual_version() {
  read -rp "Versión a instalar (ej: 1.2.3): " VERSION
  if [[ -z "$VERSION" ]]; then
    err "La versión es obligatoria en modo manual."
    exit 1
  fi

  if [[ ! "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    err "Versión inválida. Usa solo letras, números, punto, guion y guion bajo."
    exit 1
  fi
}

download_manual_archive() {
  local source="$1"
  local target="$2"

  if [[ "$source" =~ ^https?:// ]]; then
    validate_download_client
    log "Descargando artefacto desde URL..."

    if [[ "$DOWNLOAD_CLIENT" == "curl" ]]; then
      if ! curl -fL "$source" -o "$target"; then
        err "No se pudo descargar el artefacto desde la URL indicada."
        exit 1
      fi
    else
      if ! wget -q -O "$target" "$source"; then
        err "No se pudo descargar el artefacto desde la URL indicada."
        exit 1
      fi
    fi
    return
  fi

  if [[ ! -f "$source" ]]; then
    err "Archivo no encontrado: $source"
    exit 1
  fi

  log "Copiando artefacto local..."
  cp "$source" "$target"
}

# ----------------------------- VERSIONES (azcopy) ----------------------------

version_is_newer() {
  local candidate="$1" current="$2"
  [[ "$candidate" != "$current" ]] && \
    [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n1)" == "$candidate" ]]
}

version_exists_in_list() {
  local target="$1"; shift
  local values=("$@")
  for v in "${values[@]}"; do
    [[ "$v" == "$target" ]] && return 0
  done
  return 1
}

list_versions() {
  local container_sas_url="${BASE_URL}?${SAS_TOKEN}"
  log "Listando versiones disponibles para '$COMPONENT' en Azure..."

  local list_output exit_code=0
  list_output="$(azcopy list "$container_sas_url" 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    err "Error al listar blobs en Azure (código: $exit_code):"
    err "$list_output"
    err ""
    err "Verifica:"
    err "  1) SAS token válido y no expirado"
    err "  2) Permisos Read + List en el contenedor"
    err "  3) Cuenta '${STORAGE_ACCOUNT}' y contenedor '${CONTAINER_NAME}' existen"
    exit 1
  fi

  mapfile -t ALL_VERSIONS < <(
    echo "$list_output" \
      | grep -oE "${COMPONENT}/[0-9]+\.[0-9]+\.[0-9]+/app\.rar" \
      | sed -E "s|^${COMPONENT}/||;s|/app\.rar\$||" \
      | sort -Vu
  )

  if [[ ${#ALL_VERSIONS[@]} -eq 0 ]]; then
    err "No se encontraron versiones para '$COMPONENT' en Azure."
    err "Ejecuta release.sh desde la máquina de desarrollo para subir una versión."
    exit 1
  fi

  VERSIONS=("${ALL_VERSIONS[@]}")
  log "Versiones encontradas: ${ALL_VERSIONS[*]}"

  # Si hay una version instalada, ofrecer reinstall explicitamente.
  local current_link="${INSTALL_BASE}/${COMPONENT}/current"
  if [[ -L "$current_link" ]]; then
    CURRENT_VERSION="$(basename "$(readlink "$current_link")")"
    log "Versión instalada actualmente: $CURRENT_VERSION"

    local filtered=()
    for v in "${ALL_VERSIONS[@]}"; do
      version_is_newer "$v" "$CURRENT_VERSION" && filtered+=("$v")
    done

    local choices=()
    [[ ${#filtered[@]} -gt 0 ]] && choices+=("Instalar una version mas nueva")
    version_exists_in_list "$CURRENT_VERSION" "${ALL_VERSIONS[@]}" \
      && choices+=("Reinstalar actual ($CURRENT_VERSION)")
    choices+=("Elegir cualquier version" "Cancelar")

    arrow_select "¿Que deseas hacer?" "${choices[@]}"

    case "$ARROW_SELECTION" in
      "Instalar una version mas nueva")
        VERSIONS=("${filtered[@]}")
        log "Versiones mas nuevas disponibles: ${VERSIONS[*]}"
        ;;
      "Reinstalar actual ($CURRENT_VERSION)")
        VERSIONS=("$CURRENT_VERSION")
        log "Se reinstalara la version actual: $CURRENT_VERSION"
        ;;
      "Elegir cualquier version")
        VERSIONS=("${ALL_VERSIONS[@]}")
        log "Versiones disponibles para seleccion: ${VERSIONS[*]}"
        ;;
      "Cancelar")
        log "Instalacion cancelada."
        exit 0
        ;;
    esac

    if [[ ${#VERSIONS[@]} -eq 0 ]]; then
      err "No hay versiones disponibles para la opcion elegida."
      exit 1
    fi
  fi
}

select_version() {
  arrow_select "Selecciona la versión a instalar:" "${VERSIONS[@]}"
  VERSION="$ARROW_SELECTION"
}

# ----------------------------- DESCARGA Y EXTRACCIÓN -------------------------

download_and_extract() {
  local releases_dir="${INSTALL_BASE}/releases/${COMPONENT}"
  local release_dir="${releases_dir}/${VERSION}"
  local tmp_archive="/tmp/${COMPONENT}-${VERSION}-$$.rar"

  mkdir -p "$release_dir"

  if [[ "$SOURCE_MODE" == "cloud" ]]; then
    local blob_url="${BASE_URL}/${COMPONENT}/${VERSION}/app.rar?${SAS_TOKEN}"

    log "Descargando ${COMPONENT}/${VERSION}/app.rar desde Azure..."
    if ! azcopy copy "$blob_url" "$tmp_archive" \
        --overwrite=true \
        --log-level=ERROR; then
      err "Descarga fallida. Verifica el SAS token y la conectividad."
      rm -f "$tmp_archive"
      exit 1
    fi
  else
    download_manual_archive "$ARTIFACT_SOURCE" "$tmp_archive"
  fi

  log "Extrayendo en $release_dir..."
  if ! unrar x -y "$tmp_archive" "$release_dir/"; then
    err "Extracción fallida."
    rm -f "$tmp_archive"
    exit 1
  fi

  rm -f "$tmp_archive"
  RELEASE_DIR="$release_dir"
  ok "Artifact extraído en $RELEASE_DIR"
}

# ----------------------------- SYMLINK Y SERVICIO ----------------------------

update_symlink() {
  local link_dir="${INSTALL_BASE}/${COMPONENT}"
  local current_link="${link_dir}/current"
  mkdir -p "$link_dir"
  ln -sfn "$RELEASE_DIR" "$current_link"
  ok "Symlink actualizado: $current_link -> $RELEASE_DIR"
}

restart_service_if_backend() {
  if [[ "$COMPONENT" == "backend" ]]; then
    log "Reiniciando servicio backend..."
    systemctl restart backend || { err "Fallo al reiniciar backend."; exit 1; }
    ok "Servicio backend reiniciado."
  fi
}

apply_db_connection_if_backend() {
  [[ "$COMPONENT" != "backend" ]] && return
  [[ -z "${DB_CONNECTION_STRING:-}" ]] && {
    log "Sin cadena de conexión configurada. appsettings.json no será modificado."
    return
  }
  apply_connection_string_to_file "${RELEASE_DIR}/appsettings.json" "$DB_CONNECTION_STRING"
}

# ----------------------------- MAIN ------------------------------------------

require_root
select_install_source

if [[ "$SOURCE_MODE" == "cloud" ]]; then
  validate_azcopy
  load_config true
  request_sas
else
  load_config false
fi

load_db_connection_if_exists
select_component
ensure_db_connection_for_backend

if [[ "$SOURCE_MODE" == "cloud" ]]; then
  list_versions
  select_version
else
  prompt_manual_artifact_source
  prompt_manual_version
fi

download_and_extract
apply_db_connection_if_backend
update_symlink
restart_service_if_backend

log "Instalación de $COMPONENT v${VERSION} completada exitosamente (origen: $SOURCE_MODE)."
