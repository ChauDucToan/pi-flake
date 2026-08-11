{ pkgs }:
pkgs.writeShellScript "pi-check-and-sync" ''
  check_and_sync() {
    local target_file="$1"
    local source_file="$2"
    local label="$3"
    local uname="''${4:-}"
    local gname="''${5:-}"
    if [ -f "$target_file" ]; then
      if ! cmp -s "$target_file" "$source_file"; then
        echo "[NIX PROTECTED ERROR]: Found inconsistency in the content of '$target_file' ($label)" >&2
        echo "Make sure that you already backup before rebuild" >&2
        exit 1
      fi
    else
      cp "$source_file" "$target_file"
      if [ -n "$uname" ]; then chown "$uname:$gname" "$target_file"; fi
      chmod 644 "$target_file"
    fi
  }
''
