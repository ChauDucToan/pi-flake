{
  lib,
  isHM,
  defaultPackage,
}:
with lib;

let
  agentFileType = types.submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = "Filename (without `.json` extension), auto-derived from the attribute key.";
        readOnly = true;
      };

      # JSON content. Free-form `attrs` so users can paste verbatim from
      # upstream pi docs (settings.md / keybindings.md / models.md).
      value = mkOption {
        type = types.attrs;
        default = { };
        description = ''
          JSON content written verbatim to `~/.pi/agent/<name>.json`.
          Schema mirrors the corresponding upstream pi config file.
        '';
      };

      # Per-file mutable flag.
      # `true` -> file is copied once and diverges (good for `keybindings`
      # so users can rebind at runtime).
      # `false` -> symlink into store (declarative, Nix-managed).
      # Sensible default: keybindings is the only file where users tweak
      # interactively.
      mutable = mkOption {
        type = types.bool;
        default = name == "keybindings";
        description = ''
          When true, the file is copied once on first activation and then
          diverges from the Nix store. When false, it is a read-only
          symlink into the store. Defaults to true only for `keybindings`.
        '';
      };
    };
  });

  # Mark a single option as legacy via an assertion in `base-module.nix`.
  # Returns a `mkOption` declaration whose `apply` accessor would throw,
  # but more importantly whose definition triggers a clear migration error.
  # Keeping the declaration (instead of fully removing it) lets the eval
  # system surface a "you set a deprecated option" message.
  legacyOption = {
    description,
    type ? types.attrs,
    default ? { },
  }:
  mkOption {
    inherit type description default;
  };
in
{
  enable = mkEnableOption "Pi Coding Agent";

  package = mkOption {
    type = types.package;
    default = defaultPackage;
    description = "Package pi";
  };

  agentFiles = mkOption {
    type = types.attrsOf agentFileType;
    default = { };
    example = lib.literalExpression ''
      {
        settings = {
          value = {
            defaultProvider = "anthropic";
            theme = "dark";
          };
        };
        keybindings = {
          mutable = true;
          value = {
            "tui.editor.historyPrevious" = "ctrl+p";
          };
        };
        # models omitted -> pi manages ~/.pi/agent/models.json itself
      }
    '';
    description = ''
      Declarative pi config files written to `~/.pi/agent/<name>.json`.
      Each attribute key becomes the filename (without extension).

      Empty default = no files are written unless declared.
      This is the recommended way to manage pi config.
    '';
  };

  # Legacy options (deprecated, assertions in base-module.nix)
  models = legacyOption {
    type = types.attrs;
    description = ''
      **DEPRECATED.** Use `agentFiles.models` instead. See README.
    '';
  };

  # Legacy options (deprecated, assertions in base-module.nix)
  keybindings = legacyOption {
    type = types.attrsOf (types.listOf types.str);
    description = ''
      **DEPRECATED.** Use `agentFiles.keybindings` instead. See README.
    '';
  };

  # Legacy options (deprecated, assertions in base-module.nix)
  mutableDir = legacyOption {
    type = types.bool;
    default = false;
    description = ''
      **DEPRECATED.** Set `mutable = true;` per-file on `agentFiles`
      entries instead.
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
