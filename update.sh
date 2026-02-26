#!/usr/bin/env bash
set -e

CONFIG_FILE="/app/config/storage.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Configuration file $CONFIG_FILE not found." >&2
	exit 1
fi
source "$CONFIG_FILE"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }
require_root() {
	if [[ "$EUID" -ne 0 ]]; then
		err "Must be run as root."
		exit 1
	fi
}

arrow_select() {
	local prompt="$1"; shift
	local options=("$@")
	local num=${#options[@]}
	local idx
	echo "$prompt"
	echo "Escribe el número de la opción deseada y presiona Enter:"
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

prompt_sas_token() {
	if [[ -n "$AZURE_SAS_TOKEN" ]]; then
		read -rp "Reuse existing SAS token? [y/N]: " reuse
		if [[ "$reuse" =~ ^[Yy]$ ]]; then
			SAS_TOKEN="$AZURE_SAS_TOKEN"
			return
		fi
	fi
	read -rsp "Enter Azure SAS token (e.g. sv=2024-...&sig=...): " SAS_TOKEN; echo
	if [[ -z "$SAS_TOKEN" ]]; then
		err "SAS token required."
		exit 1
	fi
	# Normalize: strip leading '?' if present
	SAS_TOKEN="${SAS_TOKEN#\?}"
	log "SAS token received: ${#SAS_TOKEN} characters (...${SAS_TOKEN: -6})"
}

select_component() {
	arrow_select "Select component:" frontend backend
	COMPONENT="$ARROW_SELECTION"
}

version_is_newer() {
	local candidate="$1"
	local current="$2"
	[[ "$candidate" != "$current" ]] && [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n1)" == "$candidate" ]]
}

list_versions() {
	local url="${BASE_URL}?restype=container&comp=list&prefix=${COMPONENT}/&${SAS_TOKEN}"
	log "Fetching versions for $COMPONENT..."
	local xml
	if ! xml=$(curl -fsSL "$url"); then
		err "Failed to list blobs (HTTP error)."
		err "Verify: 1) SAS token is valid and not expired"
		err "        2) Token has 'Read' + 'List' permissions on the container"
		err "        3) Storage account and container exist"
		exit 1
	fi
	mapfile -t VERSIONS < <(echo "$xml" | grep -oP '<Name>'"${COMPONENT}/\K[^/]+(?=/app\.rar)" | sort -Vu)
	if [[ ${#VERSIONS[@]} -eq 0 ]]; then
		err "No versions found."
		exit 1
	fi
	log "Versions found: ${VERSIONS[*]}"
	# Detect current version
	local current_link="/app/${COMPONENT}/current"
	if [[ -L "$current_link" ]]; then
		CURRENT_VERSION=$(basename "$(readlink "$current_link")")
		log "Current installed version: $CURRENT_VERSION"
		FILTERED_VERSIONS=()
		for v in "${VERSIONS[@]}"; do
			if version_is_newer "$v" "$CURRENT_VERSION"; then
				FILTERED_VERSIONS+=("$v")
			fi
		done
		VERSIONS=("${FILTERED_VERSIONS[@]}")
		if [[ ${#VERSIONS[@]} -eq 0 ]]; then
			err "No newer versions available."
			exit 1
		fi
		log "Newer versions available: ${VERSIONS[*]}"
	fi
}

select_version() {
	arrow_select "Select version:" "${VERSIONS[@]}"
	VERSION="$ARROW_SELECTION"
}

download_and_extract() {
	local archive_url="${BASE_URL}/${COMPONENT}/${VERSION}/app.rar?${SAS_TOKEN}"
	local releases_dir="/app/releases/${COMPONENT}"
	local release_dir="${releases_dir}/${VERSION}"
	local tmp_archive="/tmp/${COMPONENT}-${VERSION}.rar"
	mkdir -p "$release_dir"
	log "Downloading: $archive_url"
	curl -fSL "$archive_url" -o "$tmp_archive" || { err "Download failed."; exit 1; }
	log "Extracting to $release_dir"
	unrar x -y "$tmp_archive" "$release_dir/" || { err "Extraction failed."; rm -f "$tmp_archive"; exit 1; }
	rm -f "$tmp_archive"
	RELEASE_DIR="$release_dir"
}

update_symlink() {
	local link_dir="/app/${COMPONENT}"
	local current_link="${link_dir}/current"
	mkdir -p "$link_dir"
	log "Updating symlink: $current_link -> $RELEASE_DIR"
	ln -sfn "$RELEASE_DIR" "$current_link"
}

restart_service_if_backend() {
	if [[ "$COMPONENT" == "backend" ]]; then
		log "Restarting backend service"
		systemctl restart backend || true
	fi
}

require_root
prompt_sas_token
select_component
list_versions
select_version

# Save current version for rollback
CURRENT_LINK="/app/${COMPONENT}/current"
PREVIOUS_FILE="/app/${COMPONENT}/previous_version.txt"
if [[ -L "$CURRENT_LINK" ]]; then
	CURRENT_VERSION=$(basename "$(readlink "$CURRENT_LINK")")
	echo "$CURRENT_VERSION" > "$PREVIOUS_FILE"
	log "Previous version saved: $CURRENT_VERSION"
fi

download_and_extract
update_symlink
restart_service_if_backend

log "Running healthcheck..."
if ! bash "$(dirname "$0")/healthcheck.sh" "$COMPONENT"; then
	err "Healthcheck failed. Initiating rollback."
	bash "$(dirname "$0")/rollback.sh" --component "$COMPONENT" --version "$CURRENT_VERSION"
	exit 1
fi

log "Update completed successfully."
