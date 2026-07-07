{
  lib,
  isHM,
  defaultPackage,
}:
with lib;
{
  enable = mkEnableOption "Pi Coding Agent";

  package = mkOption {
    type = types.package;
    default = defaultPackage;
    description = "Package pi";
  };

  mutableDir = mkOption {
    type = types.bool;
    default = false;
    description = "Make config editable";
  };

  extensions = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "Auto extensions";
  };

  extraEnv = mkOption {
    type = types.attrsOf (types.either types.str types.int);
    default = { };
  };

  models = mkOption {
    type = types.attrs;
    default = { };
    description = "Models setup";
  };

  keybindings = mkOption {
    type = types.attrsOf (types.listOf types.str);
    default = { };
    description = "Keybindings";
  };
}
// (
  if isHM then
    { }
  else
    {
      users = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Target users";
      };
    }
)
