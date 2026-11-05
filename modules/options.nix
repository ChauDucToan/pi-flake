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

  extensions = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      Pi package sources declared as `packages` in the generated
      `settings.json`. Pi installs them on first start; activation stays
      offline. Supports npm, Git, HTTP(S), SSH, and absolute local path
      sources accepted by `pi install`. Merged into `agentFiles.settings`
      `packages` when both are set.
    '';
  };

  extraEnv = mkOption {
    type = types.attrsOf (types.either types.str types.int);
    default = { };
    description = ''
      Extra environment variables passed to Pi. A `PATH` value is prepended
      so packaged runtime tools remain available.
    '';
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
