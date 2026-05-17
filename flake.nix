{
    description = "Pi - Your minimal agent harness";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    };

    outputs = { self, nixpkgs }: let
        systems = [
            "aarch64-darwin"
            "x86_64-darwin"
            "aarch64-linux"
            "x86_64-linux"
        ];

        forEachSystem = f: nixpkgs.lib.genAttrs systems (
            system: f {
                pkgs = nixpkgs.legacyPackages.${system};
                inherit system;
            }
        );
    in {
        packages = forEachSystem (
            { pkgs, system }:
            {
                pi-coding-agent = pkgs.callPackage ./package.nix { };
                default = self.packages.${system}.pi-coding-agent;
            }
        );

        apps = forEachSystem (
            { pkgs, system }:
            {
                pi-coding-agent = {
                    type = "app";
                    program = "${self.packages.${system}.pi-coding-agent}/bin/pi";
                };
                default = self.apps.${system}.pi-coding-agent;
            }
        );

        devShells = forEachSystem (
            { pkgs, system }:
            {
                default = pkgs.mkShell {
                    buildInputs = with pkgs; [
                        self.packages.${system}.pi-coding-agent
                    ];
                };
            }
        );

        checks = forEachSystem (
            { pkgs, system }:
            {
                pi-coding-agent = self.packages.${system}.pi-coding-agent;
                pi-version = self.packages.${system}.pi-coding-agent.passthru.tests.version;
            }
        );
    };
}
