#!/usr/bin/env bash
set -euo pipefail

PACKAGE_FILE="package-src.nix"
DUMMY_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

extract_hash_from_error() {
  local error_output="$1"
  echo "$error_output" | grep -oP 'got:\s+sha256-[A-Za-z0-9+/]+=*' | sed 's/got:[[:space:]]*//'
}

update_node_hash() {
  local old_hash="$1"
  local new_hash="$2"
  echo "Updating ${old_hash} to ${new_hash}"
  sed -i "s|outputHash = \"${old_hash}\"|outputHash = \"${new_hash}\"|" "$PACKAGE_FILE"
}

get_current_node_hash() {
  # Match only the `outputHash` line that follows `outputHashMode = "recursive"`
  # — that's unique to the `node_modules` fixed-output derivation. A bare
  # `outputHash = "..."` grep can pick up the wrong line if anything else in
  # the file ever gains one.
  sed -n '/outputHashMode = "recursive"/,/^    };/p' "$PACKAGE_FILE" \
    | grep -oP 'outputHash = "\Ksha256-[A-Za-z0-9+/]+='
}

update_node_modules() {
  local curr_hash
  curr_hash=$(get_current_node_hash)

  update_node_hash "$curr_hash" "$DUMMY_HASH"

  local err_output
  err_output=$(nix build .#pi-coding-agent-src 2>&1 || true)

  local new_hash
  new_hash=$(extract_hash_from_error "$err_output")

  if [[ -z "$new_hash" ]]; then
    echo "Can not get new hash. Build output:"
    echo "$err_output"
    update_node_hash "$DUMMY_HASH" "$curr_hash"
    exit 1
  fi

  update_node_hash "$DUMMY_HASH" "$new_hash"
  echo "node_modules hash updated: $new_hash"
}

main() {
  local version="${1:?Usage: $0 <version>}"
  nix run nixpkgs#nix-update -- pi-coding-agent-src --version "$version" --flake

  if ! nix build .#pi-coding-agent-src 2>/dev/null; then
    echo "nix-update doesn't fixing node_modules, using manual fix:"
    update_node_modules
  fi
  echo "Done!"
}

main "$@"
