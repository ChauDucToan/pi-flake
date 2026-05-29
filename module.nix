{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let 
  cfg = config.services.pi-coding-agent;

  modelsJson = pkgs.writeText "pi-models.json" (builtins.toJSON cfg.models);
  keybindingsJson = pkgs.writeText "pi-keybindings.json" (builtins.toJSON cfg.keybindings);

  piPackage = if cfg.extraEnv == {} then cfg.package else pkgs.symlinkJoin {
    name = "pi-wrapped";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/pi
      makeWrapper ${cfg.package}/bin/pi $out/bin/pi \
        ${concatStringsSep " " (mapAttrsToList (k: v: "--set ${k} ${escapeShellArg (toString v)}") cfg.extraEnv)};
    '';
  };
in {
  options.services.pi-coding-agent = {
    enable = mkEnableOption "Pi Coding Agent - Terminal-based AI coding agent";

    package = mkOption {
      type = types.package;
      default = pkgs.pi;
      description = "Flake pi-coding-agent";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "oslamelon" ];
      description = "List of users that use this configuration";
    };

    mutableDir = mkOption {
      type = types.bool;
      default = false;
      description = "Make models.json editable";
    };

    extensions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "npm:pi-subagents" ];
      description = "List of pi extensions that can install via `pi install`.";
    };

    extraEnv = mkOption {
      type = types.attrsOf (types.either types.str types.int);
      default = { };
      description = "Extra environment variable can be set through `pi`.";
    };

    models = mkOption {
      type = types.attrs;
      default = { };
      description = "Model configuration of Pi";
    };

    keybindings = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      example = {
        "tui.editor.cursorUp" = [ "up" "ctrl+p" ];
        "tui.editor.cursorDown" = [ "down" "ctrl+n" ];
      };
      description = "Cấu hình các phím tắt cho giao diện TUI của Pi (Sẽ parse thành keybindings.json).";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ piPackage ];

    system.activationScripts.piCodingAgentConfig = {
      deps = [ "users" "groups" ]; 
      text = ''
        check_and_sync() {
          local target_file="$1"
          local source_file="$2"
          local label="$3"
          local uname="$4"
          local gname="$5"
          if [ -f "$target_file" ]; then
            if ! diff -q "$target_file" "$source_file" > /dev/null; then
              echo "[NIX PROTECTED ERROR]: Found inconsistency in the content of '$target_file' ($label)" >&2
              echo "Make sure that you already backup before rebuild hoặc cập nhật lại code Nix!" >&2
              exit 1
            fi
          else
            cp "$source_file" "$target_file"
            chown "$uname:$gname" "$target_file"
            chmod 644 "$target_file"
          fi
        }
        ${concatStringsSep "\n" (map (username:
        let
          userConfig = config.users.users.${username};
          homeDir = userConfig.home;

          modelsFile = "${homeDir}/.pi/agent/models.json";
          keybindingsFile = "${homeDir}/.pi/agent/keybindings.json";
          
          installExtensionCmds = concatMapStringsSep "\n" (ext: ''
            echo "[Pi Module] installing extension: ${ext} for user ${username}..."
            runuser -l ${username} -c "export HOME=${homeDir}; ${piPackage}/bin/pi install ${ext}" || echo "Error: Can not install ${ext}"
          '') cfg.extensions;
        in ''
          mkdir -p "${homeDir}/.pi/agent"
          chown ${username}:${userConfig.group} "${homeDir}/.pi/agent"

          # MUTABLE MODE
          if ${if cfg.mutableDir then "true" else "false"}; then
            check_and_sync "${modelsFile}" "${modelsJson}" "models" "${username}" "${userConfig.group}"
            check_and_sync "${keybindingsFile}" "${keybindingsJson}" "keybindings" "${username}" "${userConfig.group}"
          else
          # IMMUTABLE MODE
            ln -sf ${modelsJson} "${modelsFile}"
            chown -h ${username}:${userConfig.group} "${modelsFile}"

            ln -sf ${keybindingsJson} "${keybindingsFile}"
            chown -h ${username}:${userConfig.group} "${keybindingsFile}"
          fi

          # Extensions
          ${installExtensionCmds}
          ''
        ) cfg.users)};
      '';
    };
  };
}
