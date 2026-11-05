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
              mapAttrsToList (
                k: v:
                if k == "PATH" then
                  "--prefix PATH : ${escapeShellArg (toString v)}"
                else
                  "--set ${k} ${escapeShellArg (toString v)}"
              ) cfg.extraEnv
            )}
        '';
      };

  # `extensions` is not installed during activation: that needs network and
  # would write into a Nix-owned settings.json. Declare them as `packages` in
  # the generated settings.json instead; Pi installs them on first start.
  fileValues =
    mapAttrs (_: entry: entry.value) cfg.agentFiles
    // optionalAttrs (cfg.extensions != [ ]) {
      settings = (cfg.agentFiles.settings.value or { }) // {
        packages = unique ((cfg.agentFiles.settings.value.packages or [ ]) ++ cfg.extensions);
      };
    };

  # Each declared file → a derivation in the Nix store.
  fileDerivations = mapAttrs (
    filename: value: pkgs.writeText "pi-${filename}.json" (builtins.toJSON value)
  ) fileValues;

  # Per-file install command for one target directory.
  # mutable -> check_and_sync (copy once, then diverge, error on drift).
  # immutable -> symlink into store.
  # `mutable` still comes from `agentFiles`; `settings` may be synthesized
  # above and have no entry there.
  installFile =
    { homeDir, username ? null, group ? null }:
    mapAttrsToList (
      filename: _:
      let
        src = fileDerivations.${filename};
        mutable = (cfg.agentFiles.${filename} or { }).mutable or false;
        target = "${homeDir}/.pi/agent/${filename}.json";
      in
      if mutable then
        ''check_and_sync "${target}" "${src}" "${filename}" ${optionalString (username != null) "${username} ${group}"}''
      else
        ''ln -sf "${src}" "${target}"
          ${optionalString (username != null) "chown -h ${username}:${group} ${escapeShellArg target}"}''
    ) fileValues;

  activationText = ''
    source ${checkAndSync}

    ${if isHM then
      ''
        # HOME MANAGER LOGIC
        HOME_DIR="${config.home.homeDirectory}"
        mkdir -p "$HOME_DIR/.pi/agent"

        ${concatStringsSep "\n" (installFile { homeDir = "$HOME_DIR"; })}
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

              ${concatStringsSep "\n" (installFile {
                inherit homeDir username;
                group = userConfig.group;
              })}
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
