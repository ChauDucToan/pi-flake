{
  lib,
  self,
  home-manager,
  eachLinuxSystem,
}:

eachLinuxSystem (
  { pkgs, system }:
  let
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
          programs.pi-coding-agent.enable = true;
        }
      ];
    };

    nixosInfo = builtins.toJSON {
      package = nixosEval.config.services.pi-coding-agent.package.pname;
      activationHash = builtins.hashString "sha256" nixosEval.config.system.activationScripts.piCodingAgentConfig.text;
    };

    homeInfo = builtins.toJSON {
      package = homeEval.config.programs.pi-coding-agent.package.pname;
      activationHash = builtins.hashString "sha256" homeEval.config.home.activation.piCodingAgentConfig.data;
    };
  in
  {
    nixos-module = pkgs.runCommand "pi-nixos-module-check" { inherit nixosInfo; } ''
      echo "$nixosInfo" > $out
    '';

    home-manager-module = pkgs.runCommand "pi-home-manager-module-check" { inherit homeInfo; } ''
      echo "$homeInfo" > $out
    '';
  }
)
