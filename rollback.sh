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

select_component() {
	local PS3="Select component: "
	select comp in frontend backend; do
		case $comp in frontend|backend) COMPONENT="$comp"; break;; *) err "Invalid.";; esac
	done
}

require_root
select_component

CURRENT_LINK="/app/${COMPONENT}/current"
RELEASES_DIR="/app/releases/${COMPONENT}"

log "Installed versions:"
mapfile -t VERSIONS < <(ls -1 "$RELEASES_DIR" | sort)
for i in "${!VERSIONS[@]}"; do echo "$((i+1))) ${VERSIONS[$i]}"; done

while true; do
	read -rp "Select version to rollback: " idx
	[[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#VERSIONS[@]} )) && PREVIOUS_VERSION="${VERSIONS[$((idx-1))]}" && break
	err "Invalid selection."
done

PREVIOUS_RELEASE_DIR="${RELEASES_DIR}/${PREVIOUS_VERSION}"
[[ ! -d "$PREVIOUS_RELEASE_DIR" ]] && err "Release directory not found." && exit 1

log "Restoring symlink: $CURRENT_LINK -> $PREVIOUS_RELEASE_DIR"
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK"

[[ "$COMPONENT" == "backend" ]] && log "Restarting backend service" && systemctl restart backend || true

log "Running healthcheck..."
if ! bash "$(dirname "$0")/healthcheck.sh"; then
	err "Healthcheck failed after rollback."
	exit 1
fi

log "Rollback completed successfully."
#!/usr/bin/env bash
set -e

# =============================================================================
# rollback.sh — Application rollback script
# Restores previous version if update fails.
# =============================================================================

APP_NAME="eb-app-code"
INSTALL_DIR="/eb-app-code"
RELEASES_DIR="$INSTALL_DIR/releases"
CURRENT_LINK="$INSTALL_DIR/current"
PREVIOUS_FILE="$INSTALL_DIR/previous_version.txt"

# Validate root privileges
if [[ "$EUID" -ne 0 ]]; then
	echo "Error: this script must be run as root." >&2
	exit 1
fi

# Check previous version file exists
if [[ ! -f "$PREVIOUS_FILE" ]]; then
	echo "Error: previous version file not found: $PREVIOUS_FILE" >&2
	exit 1
fi

# Read previous version
PREVIOUS_VERSION=$(cat "$PREVIOUS_FILE")
if [[ -z "$PREVIOUS_VERSION" ]]; then
	echo "Error: previous version value is empty." >&2
	exit 1
fi

# Check previous release directory exists
PREVIOUS_RELEASE_DIR="$RELEASES_DIR/$PREVIOUS_VERSION"
if [[ ! -d "$PREVIOUS_RELEASE_DIR" ]]; then
	echo "Error: previous release directory not found: $PREVIOUS_RELEASE_DIR" >&2
	exit 1
fi

# Restore symlink
echo "==> Restoring symlink: $CURRENT_LINK -> $PREVIOUS_RELEASE_DIR"
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK"

# Restart the systemd service
echo "==> Restarting service: $APP_NAME"
systemctl restart "$APP_NAME"

# Run healthcheck
echo "==> Running healthcheck"
if ! bash "$(dirname "$0")/healthcheck.sh"; then
	echo "Error: healthcheck failed after rollback." >&2
	exit 1
fi

echo "Rollback completed successfully"
exit 0
