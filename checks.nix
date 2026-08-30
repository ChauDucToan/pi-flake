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
    activationLogLine =
      "echo ${lib.escapeShellArg "[Pi Module] installing extension: ${activationTestExtension}..."}";
    gitPathMarker = "-git-minimal-";

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

    nixosInfo =
      assert lib.hasInfix gitPathMarker nixosActivation;
      assert lib.hasInfix activationLogLine nixosActivation;
      builtins.toJSON {
        package = nixosEval.config.services.pi-coding-agent.package.pname;
        activationHash = builtins.hashString "sha256" nixosActivation;
      };

    homeInfo =
      assert lib.hasInfix gitPathMarker homeActivation;
      assert lib.hasInfix activationLogLine homeActivation;
      builtins.toJSON {
        package = homeEval.config.programs.pi-coding-agent.package.pname;
        activationHash = builtins.hashString "sha256" homeActivation;
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
    nixos-module = pkgs.runCommand "pi-nixos-module-check" { inherit nixosInfo; } ''
      echo "$nixosInfo" > $out
    '';

    home-manager-module = pkgs.runCommand "pi-home-manager-module-check" { inherit homeInfo; } ''
      echo "$homeInfo" > $out
    '';

    package-git-path =
      packageGitPathCheck "pi-package-git-path-check" self.packages.${system}.pi-coding-agent;
    package-src-git-runtime =
      packageGitRuntimeCheck "pi-package-src-git-runtime-check" self.packages.${system}.pi-coding-agent-src;
  }
)
