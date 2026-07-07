{
  description = "Pi - Your minimal agent harness";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      lib = nixpkgs.lib;

      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      linuxSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      forSystems =
        targetSystems: f:
        lib.genAttrs targetSystems (
          system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit system;
          }
        );

      eachSystem = forSystems systems;
      eachLinuxSystem = forSystems linuxSystems;
    in
    {
      formatter = eachSystem ({ pkgs, ... }: pkgs.nixfmt);

      packages = eachSystem (
        { pkgs, system }:
        {
          pi-coding-agent = pkgs.callPackage ./package.nix { };
          pi-coding-agent-src = pkgs.callPackage ./package-src.nix { };
          default = self.packages.${system}.pi-coding-agent;
        }
      );

      nixosModules.default = import ./module.nix;
      homeManagerModules.default = import ./hm-module.nix;

      checks = import ./checks.nix {
        inherit
          lib
          self
          home-manager
          eachLinuxSystem
          ;
      };

      overlays.default = final: _: {
        pi = final.callPackage ./package.nix { };
      };
    };
}
