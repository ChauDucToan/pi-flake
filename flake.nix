{
    description = "Pi - Your minimal agent harness";

    inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

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
        
        nixosModules.default = import ./module.nix;

        homeManagerModules.default = import ./hm-module.nix;

        overlays.default = final: _: {
            pi = final.callPackage ./package.nix {};
        };
    };
}
