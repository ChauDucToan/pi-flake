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

  checkAndSync = import ./modules/check-and-sync.nix { inherit pkgs; };

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

  # `agentFiles` (new, recommended) wins over the legacy options.
  # Legacy options still work but print a migration warning.
  effectiveAgentFiles =
    let
      legacy = optionalAttrs (cfg.models != { }) {
        models = {
          value = cfg.models;
          mutable = cfg.mutableDir;
        };
      } // optionalAttrs (cfg.keybindings != { }) {
        keybindings = {
          value = cfg.keybindings;
          mutable = cfg.mutableDir;
        };
      };
    in
    warnIf (cfg.models != { })
      "[pi] `models` is deprecated. Set `agentFiles.models.value` instead."
      (warnIf (cfg.keybindings != { })
        "[pi] `keybindings` is deprecated. Set `agentFiles.keybindings.value` instead."
        (warnIf cfg.mutableDir
          "[pi] `mutableDir` is deprecated. Set `agentFiles.<name>.mutable` per file instead."
          (legacy // cfg.agentFiles)));

  # Each declared file → a derivation in the Nix store.
  fileDerivations = mapAttrs (filename: entry:
    pkgs.writeText "pi-${filename}.json" (builtins.toJSON entry.value)
  ) effectiveAgentFiles;

  # Per-file install command for one target directory.
  # mutable -> check_and_sync (copy once, then diverge, error on drift).
  # immutable -> symlink into store.
  installFile =
    { homeDir, username ? null, group ? null }:
    mapAttrsToList (filename: entry:
      let
        src = fileDerivations.${filename};
        target = "${homeDir}/.pi/agent/${filename}.json";
      in
      if entry.mutable then
        ''check_and_sync "${target}" "${src}" "${filename}" ${optionalString (username != null) "${username} ${group}"}''
      else
        ''ln -sf "${src}" "${target}"
          ${optionalString (username != null) "chown -h ${username}:${group} ${escapeShellArg target}"}''
    ) effectiveAgentFiles;

  installExtensions =
    { piExecutable, username ? null, homeDir ? "$HOME" }:
    concatMapStringsSep "\n" (ext: ''
      echo "[Pi Module] installing extension: ${ext}..."
      ${if username == null then
        ''${piExecutable} install ${escapeShellArg ext} 2>&1''
      else
        ''runuser -u ${escapeShellArg username} -- env HOME=${escapeShellArg homeDir} ${piExecutable} install ${escapeShellArg ext} 2>&1''
      }
    '') cfg.extensions;

  activationText = ''
    source ${checkAndSync}

    ${if isHM then
      ''
        # HOME MANAGER LOGIC
        HOME_DIR="${config.home.homeDirectory}"
        mkdir -p "$HOME_DIR/.pi/agent"

        ${concatStringsSep "\n" (installFile { homeDir = "$HOME_DIR"; })}

        ${installExtensions { piExecutable = "${piPackage}/bin/pi"; }}
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
            in
            ''
              install -d -o ${escapeShellArg username} -g ${escapeShellArg userConfig.group} ${escapeShellArg homeDir}/.pi
              install -d -o ${escapeShellArg username} -g ${escapeShellArg userConfig.group} ${escapeShellArg homeDir}/.pi/agent

              ${concatStringsSep "\n" (installFile { inherit homeDir username; group = userConfig.group; })}

              ${installExtensions {
                piExecutable = "${piPackage}/bin/pi";
                inherit username homeDir;
              }}
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
