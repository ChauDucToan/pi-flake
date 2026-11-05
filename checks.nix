{
  lib,
  self,
  home-manager,
  eachLinuxSystem,
}:

eachLinuxSystem (
  { pkgs, system }:
  let
    runtimeTestExtension = "git:https://127.0.0.1:1/pi-flake/test-extension";
    activationTestExtension = "git:github.com/pi-flake/test'$(touch /tmp/pi-flake-unsafe)";
    # Activation no longer runs `pi install`; it symlinks a Nix-generated
    # settings.json carrying the sources as `packages`. Pull that store path out
    # of the script by quoting (a regex capture would drop the string context).
    extractSettings =
      text:
      let
        matches = builtins.filter (part: lib.hasInfix "-pi-settings.json" part) (lib.splitString "\"" text);
      in
      if matches == [] then null else builtins.head matches;

    nixosEval = lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.default
        {
          users.users.pi-test = {
            isNormalUser = true;
            group = "users";
            home = "/home/pi-test";
          };

          services.pi-coding-agent = {
            enable = true;
            users = [ "pi-test" ];
            extensions = [ activationTestExtension ];
          };
        }
      ];
    };

    homeEval = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeManagerModules.default
        {
          home = {
            username = "pi-test";
            homeDirectory = "/home/pi-test";
            stateVersion = "25.05";
          };

          home.enableNixpkgsReleaseCheck = false;
          programs.pi-coding-agent = {
            enable = true;
            extensions = [ activationTestExtension ];
          };
        }
      ];
    };

    nixosActivation = nixosEval.config.system.activationScripts.piCodingAgentConfig.text;
    homeActivation = homeEval.config.home.activation.piCodingAgentConfig.data;

    nixosSettings = extractSettings nixosActivation;
    homeSettings = extractSettings homeActivation;

    assertionMessage = "activation must declare extensions in settings.json, not run pi install";

    nixosInfo =
      assert lib.assertMsg (nixosSettings != null) assertionMessage;
      assert lib.assertMsg (!lib.hasInfix "/bin/pi install" nixosActivation) assertionMessage;
      builtins.toJSON {
        package = nixosEval.config.services.pi-coding-agent.package.pname;
      };

    homeInfo =
      assert lib.assertMsg (homeSettings != null) assertionMessage;
      assert lib.assertMsg (!lib.hasInfix "/bin/pi install" homeActivation) assertionMessage;
      builtins.toJSON {
        package = homeEval.config.programs.pi-coding-agent.package.pname;
      };

    packageGitPathCheck =
      name: package:
      pkgs.runCommand name { } ''
        if ! grep -F ${lib.escapeShellArg "${pkgs.gitMinimal}/bin"} ${package}/bin/.pi-wrapped; then
          echo "Pi wrapper does not include Git in PATH" >&2
          exit 1
        fi
        touch $out
      '';

    packageGitRuntimeCheck =
      name: package:
      pkgs.runCommand name { } ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"

        set +e
        output=$(
          env -i \
            HOME="$HOME" \
            PATH=/definitely-missing \
            GIT_TERMINAL_PROMPT=0 \
            ${package}/bin/pi install ${lib.escapeShellArg runtimeTestExtension} 2>&1
        )
        status=$?
        set -e

        printf '%s\n' "$output"
        if printf '%s\n' "$output" | grep -F 'Executable not found in $PATH: "git"'; then
          echo "Pi could not find its packaged Git executable" >&2
          exit 1
        fi
        if ! printf '%s\n' "$output" | grep -F 'Cloning into'; then
          echo "Pi did not invoke Git as expected (exit status: $status)" >&2
          exit 1
        fi

        touch $out
      '';
  in
  {
    nixos-module =
      pkgs.runCommand "pi-nixos-module-check"
        {
          inherit nixosInfo;
          settingsFile = nixosSettings;
        }
        ''
          grep -F ${lib.escapeShellArg activationTestExtension} "$settingsFile"
          echo "$nixosInfo" > $out
        '';

    home-manager-module =
      pkgs.runCommand "pi-home-manager-module-check"
        {
          inherit homeInfo;
          settingsFile = homeSettings;
        }
        ''
          grep -F ${lib.escapeShellArg activationTestExtension} "$settingsFile"
          echo "$homeInfo" > $out
        '';

    package-git-path =
      packageGitPathCheck "pi-package-git-path-check" self.packages.${system}.pi-coding-agent;
    package-src-git-runtime =
      packageGitRuntimeCheck "pi-package-src-git-runtime-check" self.packages.${system}.pi-coding-agent-src;
  }
)
