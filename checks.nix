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
      if matches == [ ] then null else builtins.head matches;

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

    # Assert Git is reachable through the wrapper instead of grepping
    # `.pi-wrapped`: that filename is a makeWrapper detail, and the wrapper
    # shape changes when `extraEnv` adds a layer.
    packageGitPathCheck =
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
        # Assert Git itself ran; the exact wording varies by Git version.
        if ! printf '%s\n' "$output" | grep -qF 'git clone'; then
          echo "Pi did not invoke Git as expected (exit status: $status)" >&2
          exit 1
        fi

        touch $out
      '';

    # `build:binary` in package.json compiles three entrypoints and disables
    # bunfig/.env autoloading. Each miss below is silent at build time.
    packageBuildContractCheck =
      name: package:
      pkgs.runCommand name
        {
          nativeBuildInputs = [
            pkgs.binutils
            pkgs.glibc.bin
          ];
        }
        ''
          pkg=${package}/lib/pi

          for path in README.md CHANGELOG.md docs examples theme assets export-html; do
            if [ ! -e "$pkg/$path" ]; then
              echo "Missing $path in $pkg (Pi's system prompt and UI read it)" >&2
              exit 1
            fi
          done

          # pi-tui resolves native helpers from dirname(execPath)/native/...
          case ${lib.escapeShellArg pkgs.stdenvNoCC.hostPlatform.system} in
            *-linux) native=linux-platform-x11.node ;;
            *-darwin) native=darwin-platform.node ;;
            *) native= ;;
          esac
          if [ -n "$native" ] && [ -z "$(find "$pkg/native" -name "$native" -print -quit)" ]; then
            echo "Missing pi-tui native helper ($native) under $pkg/native" >&2
            exit 1
          fi

          # The helper is a prebuilt .node shipped by upstream, linked against a
          # distro libxcb. Without an RPATH it loads as "not found" and pi-tui
          # silently falls back to JS clipboard handling.
          if [ -n "$native" ] && command -v ldd >/dev/null; then
            helper=$(find "$pkg/native" -name "$native" -print -quit)
            if ldd "$helper" 2>&1 | grep -q "not found"; then
              echo "Native helper has unresolved libraries:" >&2
              ldd "$helper" 2>&1 | grep "not found" >&2
              exit 1
            fi
          fi

          # codemode's worker is resolved from the embedded $bunfs path, so it
          # only exists when worker.ts was a compile entrypoint. Match the .js
          # tail: config.ts hardcodes "extensions/codemode/worker.ts" as a string
          # and would match regardless, and the $bunfs prefix differs by build.
          if ! strings "$pkg/pi" | grep -qF 'extensions/codemode/worker.js'; then
            echo "codemode worker entrypoint was not compiled into the binary" >&2
            exit 1
          fi

          # --no-compile-autoload-bunfig / --no-compile-autoload-dotenv
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME" "$TMPDIR/cwd"
          printf 'preload = ["./does-not-exist.ts"]\n' > "$TMPDIR/cwd/bunfig.toml"
          printf 'PI_CHECK_LEAKED=1\n' > "$TMPDIR/cwd/.env"
          cd "$TMPDIR/cwd"
          if ! version=$(env -u PI_PACKAGE_DIR -u PI_CODING_AGENT_DIR "$pkg/pi" --version 2>&1); then
            echo "Pi failed to start in a directory with bunfig.toml/.env: $version" >&2
            exit 1
          fi

          # The reported version is read from package.json next to the embedded
          # bunfs root. A binary rewritten past that point (e.g. by adding an
          # RPATH to a Bun self-extracting executable) still starts but reports a
          # stale release, so compare against the packaged metadata.
          expected=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$pkg/package.json" | head -1)
          if [ "$version" != "$expected" ]; then
            echo "Pi reports version '$version' but package.json says '$expected'" >&2
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
      packageGitPathCheck "pi-package-git-path-check"
        self.packages.${system}.pi-coding-agent;
    package-src-git-runtime =
      packageGitPathCheck "pi-package-src-git-runtime-check"
        self.packages.${system}.pi-coding-agent-src;
    package-src-build-contract =
      packageBuildContractCheck "pi-package-src-build-contract-check"
        self.packages.${system}.pi-coding-agent-src;
    package-build-contract =
      packageBuildContractCheck "pi-package-build-contract-check"
        self.packages.${system}.pi-coding-agent;
  }
)
