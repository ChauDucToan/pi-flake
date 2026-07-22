#!/usr/bin/env bash
set -euo pipefail

PACKAGE_FILE="package-src.nix"
BUN_LOCK_FILE="package-src.bun.lock"
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

update_ai_data_hash() {
  local version="${1#v}"
  local old_hash new_hash
  old_hash=$(sed -n '/aiData = fetchurl {/,/  };/p' "$PACKAGE_FILE" | grep -oP 'hash = "\Ksha256-[A-Za-z0-9+/]+={0,2}')
  new_hash=$(nix hash convert --to sri --hash-algo sha256 "$(nix-prefetch-url --type sha256 "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz")")
  sed -i "/aiData = fetchurl {/,/  };/s|hash = \"${old_hash}\"|hash = \"${new_hash}\"|" "$PACKAGE_FILE"
  echo "pi-ai data hash updated: $new_hash"
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

update_bun_lock() {
  local repo_root src_path tmp source_dir
  repo_root=$(pwd)
  src_path=$(nix eval --raw .#pi-coding-agent-src.src)
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  source_dir="$tmp/source"

  cp -R "$src_path" "$source_dir"
  chmod -R u+w "$source_dir"
  if [[ -s "$repo_root/$BUN_LOCK_FILE" ]]; then
    cp "$repo_root/$BUN_LOCK_FILE" "$source_dir/bun.lock"
  fi

  (
    cd "$source_dir"
    nix shell --inputs-from "$repo_root" nixpkgs#bun -c bun install \
      --lockfile-only \
      --ignore-scripts \
      --no-progress \
      --linker hoisted
  )

  cp "$source_dir/bun.lock" "$repo_root/$BUN_LOCK_FILE"
  trap - RETURN
  rm -rf "$tmp"
  echo "bun lock updated: $BUN_LOCK_FILE"
}

main() {
  local version="${1:?Usage: $0 <version>}"
  nix run --inputs-from . nixpkgs#nix-update -- --flake --src-only --version "$version" pi-coding-agent-src
  update_ai_data_hash "$version"

  if git diff --quiet -- "$PACKAGE_FILE" && [[ -s "$BUN_LOCK_FILE" ]]; then
    echo "source package unchanged; keeping existing $BUN_LOCK_FILE"
  else
    update_bun_lock
  fi

  if ! nix build .#pi-coding-agent-src 2>/dev/null; then
    echo "node_modules hash is out of date, updating fixed-output hash:"
    update_node_modules
  fi
  echo "Done!"
}

main "$@"
