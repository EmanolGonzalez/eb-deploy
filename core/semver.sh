#!/usr/bin/env bash
# =============================================================================
# core/semver.sh — Semantic version utilities
# =============================================================================

# Validate semver format (X.Y.Z)
is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Validate version string (alphanumeric, dots, dashes, underscores)
is_valid_version() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# Compare two versions: returns 0 if v1 > v2
version_is_newer() {
  local candidate="$1" current="$2"
  [[ "$candidate" != "$current" ]] && \
    [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n1)" == "$candidate" ]]
}

# Increment a semver version
increment_version() {
  local version="$1" bump_type="${2:-patch}"
  local major minor patch

  if ! is_semver "$version"; then
    err "Version con formato inesperado: '$version'"
    return 1
  fi

  IFS='.' read -r major minor patch <<< "$version"

  case "$bump_type" in
    major) echo "$(( major + 1 )).0.0" ;;
    minor) echo "$major.$(( minor + 1 )).0" ;;
    patch) echo "$major.$minor.$(( patch + 1 ))" ;;
    *) err "Tipo de incremento invalido: $bump_type"; return 1 ;;
  esac
}
