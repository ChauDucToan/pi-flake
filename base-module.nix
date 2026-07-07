moduleType:

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  isHM = moduleType == "home-manager";
  defaultPackage = pkgs.pi or (pkgs.callPackage ./package.nix { });

  attrPath =
    if isHM then
      [
        "programs"
        "pi-coding-agent"
      ]
    else
      [
        "services"
        "pi-coding-agent"
      ];
  cfg = getAttrFromPath attrPath config;

  opts = import ./modules/options.nix {
    inherit lib isHM defaultPackage;
  };

  modelsJson = pkgs.writeText "pi-models.json" (builtins.toJSON cfg.models);
  keybindingsJson = pkgs.writeText "pi-keybindings.json" (builtins.toJSON cfg.keybindings);

  piPackage =
    if cfg.extraEnv == { } then
      cfg.package
    else
      pkgs.symlinkJoin {
        name = "pi-wrapped";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm $out/bin/pi
          makeWrapper ${cfg.package}/bin/pi $out/bin/pi \
            ${concatStringsSep " " (
              mapAttrsToList (k: v: "--set ${k} ${escapeShellArg (toString v)}") cfg.extraEnv
            )}
        '';
      };

  activationText = ''
    check_and_sync() {
      local target_file="$1"
      local source_file="$2"
      local label="$3"
      local uname="$4"
      local gname="$5"
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

    ${
      if isHM then
        ''
          # HOME MANAGER LOGIC
          HOME_DIR="${config.home.homeDirectory}"
          mkdir -p "$HOME_DIR/.pi/agent"

          if ${if cfg.mutableDir then "true" else "false"}; then
            check_and_sync "$HOME_DIR/.pi/agent/models.json" "${modelsJson}" "models" "" ""
            check_and_sync "$HOME_DIR/.pi/agent/keybindings.json" "${keybindingsJson}" "keybindings" "" ""
          else
            ln -sf "${modelsJson}" "$HOME_DIR/.pi/agent/models.json"
            ln -sf "${keybindingsJson}" "$HOME_DIR/.pi/agent/keybindings.json"
          fi

          ${concatMapStringsSep "\n" (ext: ''
            echo "[Pi Module] installing extension: ${ext}..."
            ${piPackage}/bin/pi install ${escapeShellArg ext} 2>&1
          '') cfg.extensions}
        ''
      else
        ''
          # NIXOS LOGIC
          ${concatStringsSep "\n" (
            map (
              username:
              let
                userConfig = config.users.users.${username};
                homeDir = userConfig.home;
                modelsFile = "${homeDir}/.pi/agent/models.json";
                keybindingsFile = "${homeDir}/.pi/agent/keybindings.json";

                installExtensionCmds = concatMapStringsSep "\n" (ext: ''
                  echo "[Pi Module] installing extension: ${ext} for user ${username}..."
                  runuser -u ${escapeShellArg username} -- env HOME=${escapeShellArg homeDir} ${piPackage}/bin/pi install ${escapeShellArg ext} 2>&1
                '') cfg.extensions;
              in
              ''
                install -d -o ${escapeShellArg username} -g ${escapeShellArg userConfig.group} ${escapeShellArg homeDir}/.pi
                install -d -o ${escapeShellArg username} -g ${escapeShellArg userConfig.group} ${escapeShellArg homeDir}/.pi/agent

                if ${if cfg.mutableDir then "true" else "false"}; then
                  check_and_sync "${modelsFile}" "${modelsJson}" "models" "${username}" "${userConfig.group}"
                  check_and_sync "${keybindingsFile}" "${keybindingsJson}" "keybindings" "${username}" "${userConfig.group}"
                else
                  ln -sf "${modelsJson}" "${modelsFile}"
                  chown -h ${username}:${userConfig.group} "${modelsFile}"

                  ln -sf "${keybindingsJson}" "${keybindingsFile}"
                  chown -h ${username}:${userConfig.group} "${keybindingsFile}"
                fi
                ${installExtensionCmds}
              ''
            ) cfg.users
          )}
        ''
    }
  '';
in
{
  disabledModules = lib.optional isHM "programs/pi-coding-agent.nix";

  options = setAttrByPath attrPath opts;

  config = mkIf cfg.enable (mkMerge [
    (
      if isHM then
        {
          home.packages = [ piPackage ];
          home.activation.piCodingAgentConfig = config.lib.dag.entryAfter [ "writeBoundary" ] activationText;
        }
      else
        {
          environment.systemPackages = [ piPackage ];
          system.activationScripts.piCodingAgentConfig = {
            deps = [
              "users"
              "groups"
            ];
            text = activationText;
          };
        }
    )
  ]);
}
