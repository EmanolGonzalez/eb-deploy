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
require_root() { [[ "$EUID" -ne 0 ]] && err "Must be run as root." && exit 1; }

prompt_sas_token() {
	if [[ -n "$AZURE_SAS_TOKEN" ]]; then
		read -rp "Reuse existing SAS token? [y/N]: " reuse
		[[ "$reuse" =~ ^[Yy]$ ]] && SAS_TOKEN="$AZURE_SAS_TOKEN" && return
	fi
	read -rsp "Enter Azure SAS token (starts with ?): " SAS_TOKEN; echo
	[[ -z "$SAS_TOKEN" ]] && err "SAS token required." && exit 1
}

select_component() {
	local PS3="Select component: "
	select comp in frontend backend; do
		case $comp in frontend|backend) COMPONENT="$comp"; break;; *) err "Invalid.";; esac
	done
}

list_versions() {
	local url="${BASE_URL}/${COMPONENT}?restype=container&comp=list${SAS_TOKEN}"
	log "Fetching versions for $COMPONENT..."
	local xml; xml=$(curl -fsSL "$url") || { err "Failed to list blobs."; exit 1; }
	VERSIONS=($(echo "$xml" | grep -oP '<Name>'"${COMPONENT}/\K[0-9.]+(?=/app\.rar)</Name>" | sort -u))
	[[ ${#VERSIONS[@]} -eq 0 ]] && err "No versions found." && exit 1
}

select_version() {
	log "Available versions:"; local i=1
	for v in "${VERSIONS[@]}"; do echo "  $i) $v"; ((i++)); done
	while true; do
		read -rp "Enter version number: " idx
		[[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#VERSIONS[@]} )) && VERSION="${VERSIONS[$((idx-1))]}" && break
		err "Invalid selection."
	done
}

download_and_extract() {
	local archive_url="${BASE_URL}/${COMPONENT}/${VERSION}/app.rar${SAS_TOKEN}"
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
	[[ "$COMPONENT" == "backend" ]] && log "Restarting backend service" && systemctl restart backend || true
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
if ! bash "$(dirname "$0")/healthcheck.sh"; then
	err "Healthcheck failed. Initiating rollback."
	bash "$(dirname "$0")/rollback.sh"
	exit 1
fi

log "Update completed successfully."
#!/usr/bin/env bash
set -e

# =============================================================================
# update.sh — Application update script
# Updates to a new version, keeps previous version for rollback.
# =============================================================================

APP_NAME="eb-app-code"
INSTALL_DIR="/eb-app-code"
RELEASES_DIR="$INSTALL_DIR/releases"
CURRENT_LINK="$INSTALL_DIR/current"
PREVIOUS_FILE="$INSTALL_DIR/previous_version.txt"
BASE_URL="https://YOUR_STORAGE_ACCOUNT.blob.core.windows.net/releases"
SAS_TOKEN="?YOUR_SAS_TOKEN"

# Validate version argument
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
	echo "Error: version argument is required." >&2
	echo "Usage: bash update.sh <version>" >&2
	exit 1
fi

# Validate root privileges
if [[ "$EUID" -ne 0 ]]; then
	echo "Error: this script must be run as root." >&2
	exit 1
fi

# Detect current version and save for rollback
if [[ -L "$CURRENT_LINK" ]]; then
	CURRENT_VERSION=$(basename $(readlink "$CURRENT_LINK"))
	echo "$CURRENT_VERSION" > "$PREVIOUS_FILE"
	echo "==> Previous version saved: $CURRENT_VERSION"
else
	echo "Warning: current symlink not found, skipping previous version save."
fi

# Download new release archive
ARCHIVE_NAME="app-${VERSION}.rar"
DOWNLOAD_URL="${BASE_URL}/${ARCHIVE_NAME}${SAS_TOKEN}"
TMP_ARCHIVE="/tmp/${ARCHIVE_NAME}"

echo "==> Downloading ${ARCHIVE_NAME}"
if ! curl -fSL "$DOWNLOAD_URL" -o "$TMP_ARCHIVE"; then
	echo "Error: failed to download ${ARCHIVE_NAME} from storage." >&2
	exit 1
fi

# Extract archive into versioned release directory
RELEASE_DIR="${RELEASES_DIR}/${VERSION}"
echo "==> Extracting archive to ${RELEASE_DIR}"
mkdir -p "$RELEASE_DIR"
unrar x -y "$TMP_ARCHIVE" "$RELEASE_DIR/"
rm -f "$TMP_ARCHIVE"

# Update the 'current' symlink to point to the new release
echo "==> Updating symlink: ${CURRENT_LINK} -> ${RELEASE_DIR}"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

# Restart the systemd service
echo "==> Restarting service: $APP_NAME"
systemctl restart "$APP_NAME"

# Run healthcheck
echo "==> Running healthcheck"
if ! bash "$(dirname "$0")/healthcheck.sh"; then
	echo "Error: healthcheck failed after update. Initiating rollback." >&2
	bash "$(dirname "$0")/rollback.sh"
	exit 1
fi

echo "Update completed successfully"
exit 0
