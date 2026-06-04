#!/usr/bin/env bash
set -euo pipefail

PACKAGE_FILE="package.nix"
BASE_URL="https://github.com/earendil-works/pi/releases/download/v"

# Nix system -> upstream tarball filename.
# Must match the `url = "..."` entries in package.nix exactly.
declare -A TARBALLS=(
  ["x86_64-linux"]="pi-linux-x64.tar.gz"
  ["aarch64-linux"]="pi-linux-arm64.tar.gz"
  ["x86_64-darwin"]="pi-darwin-x64.tar.gz"
  ["aarch64-darwin"]="pi-darwin-arm64.tar.gz"
)

prefetch_src_hash() {
  local url="$1"
  # nix-prefetch-url prints the bare nixbase32 hash; convert to SRI form
  # so the output matches the `hash = "sha256-..."` style in package.nix.
  local raw
  raw=$(nix-prefetch-url --type sha256 "$url")
  nix hash convert --to sri --hash-algo sha256 "$raw"
}

update_hash_for_system() {
  local system="$1"
  local tarball="$2"
  local new_hash="$3"
  local url_pattern="$tarball"

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

  for system in "${!TARBALLS[@]}"; do
    local tarball="${TARBALLS[$system]}"
    local url="${base_url}/${tarball}"
    echo "Fetching: $url"
    local new_hash
    new_hash=$(prefetch_src_hash "$url")
    update_hash_for_system "$system" "$tarball" "$new_hash"
  done

  echo "Done!"
}

main "$@"
