# pi-flake

> ⚠️ **Migration notice — `models`, `keybindings`, `mutableDir` are deprecated.**
> Use [`agentFiles`](#agentfiles) instead. Old options still work for now but print a deprecation warning on every evaluation. See [Migration](#migration-from-models--keybindings) below.

Nix flake for **[Pi](https://github.com/earendil-works/pi)** – a minimal, terminal-based AI coding agent built with Bun.

This flake provides:

- A **package** (`pi-coding-agent`) – the compiled Pi binary
- A **NixOS module** – system-wide configuration with per-user support
- A **Home Manager module** – per-user declarative configuration
- An **overlay** – to make `pi` available in your own Nixpkgs

---

## Why `agentFiles`?

The previous design declared `models` and `keybindings` as separate options and always wrote (or symlinked) both files at `~/.pi/agent/`. This broke users who want to manage `models.json` and API keys imperatively (e.g. via the Pi CLI) while still declaring `keybindings` (or `settings`) declaratively. See [issue #32](https://github.com/ChauDucToan/pi-flake/issues/32).

The new `agentFiles` option is an `attrsOf submodule` – each attribute key becomes the filename (`~/.pi/agent/<key>.json`) and you only declare the files you actually want Nix to manage. By default, **no files are written** (no-op on default), so Pi is free to manage its own config files imperatively.

---

## Quick Start

### 1. Add the flake

In your `flake.nix` inputs:

```nix
inputs = {
  pi-flake.url = "github:oslamelon/pi-flake";
  # optional, if you use Home Manager:
  home-manager.url = "github:nix-community/home-manager";
};
```

### 2. Install the package globally (without a module)

```nix
{
  inputs.pi-flake.url = "github:oslamelon/pi-flake";

  outputs = { self, nixpkgs, pi-flake }: {
    nixosConfigurations.myMachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # optional: make `pi` available via the overlay
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ pi-flake.overlays.default ];
          environment.systemPackages = [ pkgs.pi ];
        })
      ];
    };
  };
}
```

Then run `pi --help` to verify.

---

## Configuration Options

All three approaches (NixOS module, Home Manager module, standalone) share the same base options.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` | `false` | Enable the Pi Coding Agent module |
| `package` | `package` | `pkgs.pi` | Pi package to use (useful for overriding) |
| `agentFiles` | `attrsOf submodule` | `{}` | **Recommended.** Per-file declarative config. See [`agentFiles`](#agentfiles). |
| `extensions` | `list of string` | `[]` | List of Pi extensions to auto-install on activation |
| `extraEnv` | `attrs of (string or int)` | `{}` | Extra environment variables passed to the Pi binary |
| `users` **†** | `list of string` | `[]` | Target users for system-wide configuration |

### Deprecated (still work, prints warning)

| Option | Type | Default | Migration |
|--------|------|---------|-----------|
| `models` | `attrs` | `{}` | → `agentFiles.models.value` |
| `keybindings` | `attrs of (list of string)` | `{}` | → `agentFiles.keybindings.value` |
| `mutableDir` | `bool` | `false` | → per-file `agentFiles.<name>.mutable` |

**†** Only available in the NixOS module.

---

## `agentFiles`

`agentFiles` is an `attrsOf submodule` where each entry becomes one file under `~/.pi/agent/`. The attribute key is the filename (without `.json` extension); the `value` field is the JSON content written verbatim.

### Schema

```nix
agentFiles.<name> = {
  value = { ... };         # JSON content, written verbatim to ~/.pi/agent/<name>.json
  mutable = false;         # optional, default = false (true for `keybindings`)
};
```

- `value`: free-form `attrs` – paste verbatim from upstream Pi docs (see links below).
- `mutable`:
  - `false` (default) → file is a **read-only symlink** into the Nix store.
  - `true` → file is **copied once** on first activation and then diverges; subsequent rebuilds will fail if the file drifts from the declared config (use `mutable = true` for files you want to tweak at runtime, e.g. `keybindings`).
  - Default for `keybindings` is `true`; default for everything else is `false`.

### Filenames

The attribute key must match the upstream Pi config file name. Currently documented:

| Key | File | See |
|---|---|---|
| `settings` | `~/.pi/agent/settings.json` | [settings.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md) |
| `keybindings` | `~/.pi/agent/keybindings.json` | [keybindings.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/keybindings.md) |
| `models` | `~/.pi/agent/models.json` | [models.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md) |

If you only declare a subset (e.g. just `keybindings`), Pi will manage the other files itself imperatively.

### Example

```nix
programs.pi-coding-agent = {
  enable = true;

  agentFiles = {
    settings = {
      value = {
        defaultProvider = "anthropic";
        defaultModel = "claude-sonnet-4-5-20250929";
        theme = "dark";
      };
    };

    keybindings = {
      # mutable defaults to true for `keybindings`, so you can rebind at runtime
      value = {
        "tui.editor.historyPrevious" = "ctrl+p";
        "tui.editor.historyNext" = "ctrl+n";
      };
    };

    # models intentionally omitted → Pi manages ~/.pi/agent/models.json itself
    # (e.g. via `pi /login` or its own config command).
  };
};
```

### Disable a file temporarily

To stop Nix from managing a file, **remove the corresponding key from `agentFiles`**. Pi will then take over its own file. Don't comment out the value – that would still write the file.

### Filename validation

The `name` field is `readOnly` and auto-derived from the attribute key. Nix will reject keys that aren't valid filenames at evaluation time.

---

## Migration from `models` / `keybindings`

Old config:

```nix
mutableDir = true;
models = {
  default = { provider = "openai"; model = "gpt-4o"; };
};
keybindings = {
  "mode:main:key:ctrl-p" = [ "goto:chat" ];
};
```

New config:

```nix
agentFiles = {
  models = {
    mutable = true;            # was: mutableDir = true
    value = {
      default = { provider = "openai"; model = "gpt-4o"; };
    };
  };
  keybindings = {
    # mutable defaults to true for `keybindings`
    value = {
      "mode:main:key:ctrl-p" = [ "goto:chat" ];
    };
  };
};
```

If both old and new options are set for the same file, `agentFiles` wins.

---

## Usage on NixOS

```nix
{
  imports = [ pi-flake.nixosModules.default ];

  services.pi-coding-agent = {
    enable = true;

    users = [ "alice" "bob" ];

    agentFiles = {
      settings = {
        value = {
          defaultProvider = "anthropic";
          theme = "dark";
        };
      };
      keybindings = {
        value = {
          "tui.editor.historyPrevious" = "ctrl+p";
        };
      };
    };

    extensions = [ "github:user/repo" ];

    extraEnv = {
      PI_THEME = "catppuccin-mocha";
      PI_LOG_LEVEL = "info";
    };
  };
}
```

### How it works

On every system activation, the module:

1. Creates `~/.pi/agent/` for each configured user.
2. For each entry in `agentFiles`, writes (or symlinks) `~/.pi/agent/<name>.json` per the per-file `mutable` flag.
3. Files **not** in `agentFiles` are left untouched — Pi manages them itself.
4. Runs `pi install <ext>` during activation for every extension declared in `extensions`.

---

## Usage with Home Manager

```nix
{
  imports = [ pi-flake.homeManagerModules.default ];

  programs.pi-coding-agent = {
    enable = true;

    agentFiles = {
      settings = {
        value = {
          defaultProvider = "anthropic";
          theme = "dark";
        };
      };
      keybindings = {
        value = {
          "tui.editor.historyPrevious" = "ctrl+p";
        };
      };
    };

    extensions = [ "github:some/extension" ];
    extraEnv = { OPENAI_API_KEY = "sk-..."; };
  };
}
```

Differences from the NixOS module:

- The option path is `programs.pi-coding-agent` instead of `services.pi-coding-agent`.
- There is **no `users` option** – it always targets your Home Manager user.
- `home.packages` is used to install the binary.
- Configuration is applied via `home.activation` (after `writeBoundary`).

---

## Usage through a plain Nix overlay

If you don't want the modules, just use the overlay to get the `pi` package:

### In a NixOS configuration

```nix
{
  nixpkgs.overlays = [ pi-flake.overlays.default ];
  environment.systemPackages = [ pkgs.pi ];
}
```

### In `home.nix` (without the HM module)

```nix
{ pkgs, ... }: {
  nixpkgs.overlays = [ inputs.pi-flake.overlays.default ];
  home.packages = [ pkgs.pi ];
}
```

### In a standalone shell

```nix
{
  inputs.pi-flake.url = "github:oslamelon/pi-flake";

  outputs = { pi-flake, ... }: pi-flake.packages.x86_64-linux.default;
}
```

Then run `nix run github:oslamelon/pi-flake` to try Pi directly.

---

## Package customization

Override the source, version, or build inputs via `package` option or `pkgs.callPackage`:

```nix
{ pkgs, pi-flake, ... }: {
  services.pi-coding-agent = {
    enable = true;
    package = pkgs.pi.overrideAttrs (old: {
      version = "0.78.0";
      src = pkgs.fetchFromGitHub {
        owner = "earendil-works";
        repo = "pi";
        rev = "v0.78.0";
        hash = "...";
      };
    });
  };
}
```

---

## Available outputs

| Output | Description |
|--------|-------------|
| `packages.<system>.pi-coding-agent` | The compiled Pi package |
| `packages.<system>.default` | Alias for `pi-coding-agent` |
| `nixosModules.default` | NixOS module (`services.pi-coding-agent`) |
| `homeManagerModules.default` | Home Manager module (`programs.pi-coding-agent`) |
| `overlays.default` | Overlay exposing `pi` in `pkgs` |

Supported systems: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`.

---

## Development

```bash
# Build the package
nix build .

# Check the flake
nix flake check

# Update dependencies
nix flake update
```

---

## License

MIT – see [LICENSE](./LICENSE).
