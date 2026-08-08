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

  mutableDirBackupOnConflict = mkOption {
    type = types.bool;
    default = false;
    description = ''
      When `mutableDir = true` and an existing config file differs from the
      declared one, back it up to `<file>.backup` instead of failing the
      activation. Only useful if you accept silently losing the declaration
      drift on every rebuild.
    '';
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
    # Keep the providers freeform: pi's schema is extensible (custom APIs
    # registered by extensions, per-model compat maps, etc.), and a strict
    # submodule would inject default/null keys into the JSON that pi does not
    # expect. We only enforce the top-level `providers` key here.
    type = types.submodule {
      freeformType = types.attrs;
      options.providers = mkOption {
        type = types.attrsOf types.attrs;
        default = { };
        description = "Custom providers, keyed by provider name.";
      };
    };
    default = { };
    description = ''
      Models setup, written to `~/.pi/agent/models.json`. See
      https://pi.dev/docs/latest/models for the full schema.

      Prefer referencing secrets via environment variables (`$MY_API_KEY`) or a
      shell command (`!op read ...`) instead of literal values: the file is a
      world-readable symlink into the nix store.
    '';
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
