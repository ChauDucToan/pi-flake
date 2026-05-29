# pi-flake

Nix flake for **[Pi](https://github.com/earendil-works/pi)** – a minimal, terminal-based AI coding agent built with Bun.

This flake provides:

- A **package** (`pi-coding-agent`) – the compiled Pi binary
- A **NixOS module** – system-wide configuration with per-user support
- A **Home Manager module** – per-user declarative configuration
- An **overlay** – to make `pi` available in your own Nixpkgs

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
| `mutableDir` | `bool` | `false` | When `true`, config files are copied and editable; when `false` they are read-only symlinks into the Nix store |
| `extensions` | `list of string` | `[]` | List of Pi extensions to auto-install on activation |
| `extraEnv` | `attrs of (string or int)` | `{}` | Extra environment variables passed to the Pi binary |
| `models` | `attrs` | `{}` | Models configuration (written to `~/.pi/agent/models.json`) |
| `keybindings` | `attrs of (list of string)` | `{}` | Keybinding overrides (written to `~/.pi/agent/keybindings.json`) |
| `users` **†** | `list of string` | `[]` | Target users for system-wide configuration |

**†** Only available in the NixOS module.

---

## Usage on NixOS

Add the module to your NixOS configuration:

```nix
{
  imports = [ pi-flake.nixosModules.default ];

  services.pi-coding-agent = {
    enable = true;

    # Which users should get Pi configured
    users = [ "alice" "bob" ];

    # Make config files mutable (editable by the user)
    mutableDir = true;

    # Models configuration (saved as ~/.pi/agent/models.json)
    models = {
      default = {
        provider = "openai";
        model = "gpt-4o";
      };
      local = {
        provider = "ollama";
        model = "codellama";
        baseUrl = "http://127.0.0.1:11434";
      };
    };

    # Keybinding overrides (saved as ~/.pi/agent/keybindings.json)
    keybindings = {
      "mode:main:key:ctrl-p" = [ "goto:chat" ];
      "mode:chat:key:escape" = [ "goto:main" ];
    };

    # Auto-install these Pi extensions
    extensions = [
      "github:user/repo"
    ];

    # Extra environment variables
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
2. Writes (or symlinks) `models.json` and `keybindings.json` inside it.
3. If `mutableDir = false` (default), the files are **read-only symlinks** into the Nix store — any manual edits will be lost on rebuild. The module also **guards against accidental edits**: if you mutate a mutable file and it differs from the declared config, activation will fail with a clear error message asking you to back up first.
4. Runs `pi install <ext>` for every extension declared in `extensions`.

> **Note:** `models` and `keybindings` are fully replaced on every rebuild. If you need to keep local edits, set `mutableDir = true`.

---

## Usage with Home Manager

```nix
{
  imports = [ pi-flake.homeManagerModules.default ];

  programs.pi-coding-agent = {
    enable = true;

    mutableDir = true;

    models = {
      default = {
        provider = "openai";
        model = "gpt-4o";
        apiKey = "$OPENAI_API_KEY"; # reference an env variable
      };
    };

    keybindings = {
      "mode:main:key:ctrl-p" = [ "goto:chat" ];
    };

    extensions = [ "github:some/extension" ];

    extraEnv = {
      OPENAI_API_KEY = "sk-...";
    };
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
