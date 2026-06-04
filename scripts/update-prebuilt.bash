#!/usr/bin/env bash
set -euo pipefail

PACKAGE_FILE="package.nix"
SYSTEMS=(
  "x86_64-linux"
  "aarch64-linux"
  "x86_64-darwin"
  "aarch64-darwin"
)
BASE_URL="https://github.com/ChauDucToan/pi-flake/releases/download/v"

prefetch_src_hash() {
  local url="$1"
  nix-prefetch-url --type sha256 "$url"
}

update_hash_for_system() {
  local system="$1"
  local new_hash="$2"
  local url_pattern="pi-${system}.tar.gz"

  # URL line for this system must be unique
  local match_count
  match_count=$(grep -cF "$url_pattern" "$PACKAGE_FILE")
  if [[ "$match_count" -ne 1 ]]; then
    echo "Error: URL pattern '$url_pattern' should match exactly 1 line (got $match_count)" >&2
    exit 1
  fi

  local url_line hash_line
  url_line=$(grep -nF "$url_pattern" "$PACKAGE_FILE" | cut -d: -f1)
  hash_line=$((url_line + 1))

  # Sanity check: line after URL must be a hash line
  if ! sed -n "${hash_line}p" "$PACKAGE_FILE" | grep -qE '^[[:space:]]+hash = "sha256-'; then
    echo "Error: line ${hash_line} of $PACKAGE_FILE is not a hash line" >&2
    echo "Got: $(sed -n "${hash_line}p" "$PACKAGE_FILE")" >&2
    exit 1
  fi

  sed -i "${hash_line}s#hash = \"sha256-[^\"]*\"#hash = \"${new_hash}\"#" "$PACKAGE_FILE"
  echo "  updated: $system -> $new_hash"
}

main() {
  local version="${1:?Usage: $0 <version> (e.g. v0.78.0)}"
  # Normalize: accept both '0.78.0' and 'v0.78.0'
  local version_num="${version#v}"
  local base_url="${BASE_URL}${version_num}"

  echo "Prefetching src hashes for version ${version}..."

  for system in "${SYSTEMS[@]}"; do
    local url="${base_url}/pi-${system}.tar.gz"
    echo "Fetching: $url"
    local new_hash
    new_hash=$(prefetch_src_hash "$url")
    update_hash_for_system "$system" "$new_hash"
  done

  echo "Done!"
}

main "$@"
