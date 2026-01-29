## Flake templates

This repository publishes a web development template that you can use via Nix flakes:

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
```

It provides:
- Dev shell with Node.js 22, pnpm, bun, Cloudflare wrangler, AWS CLI v2, jq/yq, mkcert, just
- Prettier formatting integrated via treefmt-nix and exposed as `apps.format`
- `nix run .#dev` for development tasks and `nix flake check` hooks

# dotfiles

## Prerequisites
- Nix(Lix or Determinate's vanilla)

## Profiles (Denix hosts/rices)

This flake uses [Denix](https://github.com/yunfachi/denix) to build macOS configurations.

- Hosts: `a2m_mac` (default rice: `full`), `mn_mac` (default rice: `mn`).
- Rices: `full`, `minimum`, `mn`.
  - `minimum`: minimal setup with Git and GPG only (no GUI/dev stacks).
  - `mn`: based on `full` with the same tooling set, including AI coding CLIs.

CLI usage examples (recommended):

```bash
# Apply default rice for each host
nix run .#apply -- --host a2m_mac
nix run .#apply -- --host mn_mac

# Build only (no switch)
nix run .#apply -- --host a2m_mac --action build

# Switch rices per host
nix run .#apply -- --host a2m_mac --rice minimum
nix run .#apply -- --host mn_mac --rice minimum
```

Manual attribute examples (still valid):
`a2m_mac`, `mn_mac`, `a2m_mac-minimum`, `mn_mac-minimum`.

When `--rice` is provided, the CLI tries `host-rice` first and falls back to `host` if the rice matches the host default.

## Terminal Compatibility

**For macOS users**: Please use a 24-bit True Color compatible terminal instead of the default Terminal.app. The Starship prompt configuration in this repository uses True Color (#RRGGBB) values that are only properly displayed in terminals with full color support.

**Recommended terminals:**
- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

**Why this matters**: macOS Terminal.app only supports 256-color palette, which causes the Starship prompt colors to be approximated and appear different from the intended design. True Color terminals can display the full 16.7 million color spectrum, ensuring consistent visual appearance.

## Local Facts + Secrets (Override Inputs)

This repo no longer uses Git clean/smudge filters. Machine-specific facts and secrets live outside Git and are injected at build time using flake overrides.

### Facts (non-secret)

- Create `~/.config/dotfiles-local/facts.nix`
- Required: `user.username`, `user.homeDirectory`

Example `facts.nix`:
```nix
{
  user = {
    username = "yourname";
    fullName = "Your Name";
    email = "you@example.com";
    homeDirectory = "/Users/yourname";
    platform = "aarch64-darwin";
    stateVersion = {
      home = "25.05";
      darwin = 6;
    };
  };

  machines = {
    a2m_mac = {
      computerName = "Your Mac";
      localHostName = "your-mac";
      hostName = "your-mac.local";
    };
  };
}
```

### Secrets (confidential)

- Create `~/.config/dotfiles-secrets/`
- Define `secrets.nix` and encrypted files (sops+age recommended)

Example `secrets.nix`:
```nix
{
  files = {
    aiEnv = {
      sopsFile = ./files/ai.env.sops.yaml;
      targetPath = ".config/dotfiles/secrets/ai.env";
      mode = "0600";
    };
  };
}
```

Optional shell sourcing (in `~/.zshrc`):
```bash
if [ -f "$HOME/.config/dotfiles/secrets/ai.env" ]; then
  source "$HOME/.config/dotfiles/secrets/ai.env"
fi
```

### Build with overrides

All `nix run .#apply|.#update|.#doctor|.#bootstrap` commands pass overrides automatically. Manual invocations still need them:

```bash
darwin-rebuild build --flake .#a2m_mac \
  --override-input local path:$HOME/.config/dotfiles-local \
  --override-input secrets path:$HOME/.config/dotfiles-secrets
```

**Note**: `nix/local/` and `nix/secrets/` in the repo are stubs for public evaluation (templates only). Real configurations require `--override-input` and should not include a `STUB` file.

## Binary Cache (Cachix / Attic)

This repo can pull from extra binary caches via your local facts.

Add to `~/.config/dotfiles-local/facts.nix`:
```nix
{
  binaryCaches = {
    substituters = [
      "https://your-cache.cachix.org"
      # "https://attic.example.org/your-cache"
    ];
    trustedPublicKeys = [
      "your-cache.cachix.org-1:REPLACE_WITH_PUBLIC_KEY"
      # "attic.example.org-1:REPLACE_WITH_PUBLIC_KEY"
    ];
  };
}
```

CI cache pushes are wired for Cachix. Set these in the GitHub repo:
- `CACHIX_CACHE_NAME` (repository variable)
- `CACHIX_AUTH_TOKEN` (repository secret, write-enabled)

Once set, the macOS CI job builds `darwinConfigurations.*.system` and pushes results to the cache.

## Karabiner-Elements Setup

This repository includes comprehensive keyboard layouts and input method configurations for Karabiner-Elements in the `keyboards/karabiner/complex_modifications/` directory.

### Available Configurations

1. **japanese-input-toggle.json**: Japanese input method switching configurations
   - Command/Control/Option/Shift keys for 英数・かな switching
   - Caps Lock toggle functionality
   - Vim-friendly ESC key behavior
   - Based on KE-complex_modifications

2. **spacebar-to-shift.json**: Space-and-Shift (SandS) functionality
   - Spacebar acts as Left Shift when held with other keys
   - Normal space character when pressed alone
   - Based on KE-complex_modifications

3. **vylet-alt-layout.json**: Vylet alternative keyboard layout
   - Complete keyboard layout remapping
   - Created by MightyAcas
   - Optimized for efficient typing

4. **shingeta_en.json**: 新下駄配列 (Shingeta layout) for English typing games
   - Japanese keyboard layout optimized for typing games
   - Created by kouy, implemented by funatsufumiya

5. **shingeta_jp.json**: 新下駄配列 (Shingeta layout) for Japanese input
   - Full Japanese input support
   - Same layout as above but for general Japanese typing

### Manual Setup

To use the keyboard configurations from this dotfiles repository:

#### Option 1: Automated Setup with Nix (Recommended)

If you're using this dotfiles repository with Nix and home-manager, the Karabiner-Elements configurations are automatically set up through symbolic links.

The configuration is managed in `nix/denix/modules/karabiner.nix` and will automatically:
1. Create the necessary directories
2. Generate symbolic links for all configuration files
3. Keep the links updated when you rebuild your configuration

**Configuration Details:**
- Configuration files are sourced from the `keyboards/` directory in this repo
- All configuration files are automatically discovered and linked
- The setup is declarative and version-controlled
- Changes take effect after running `darwin-rebuild switch --flake .`

#### Option 2: Manual Setup

For manual setup or if not using Nix:

1. Create the Karabiner-Elements configuration directory:
   ```bash
   mkdir -p ~/.config/karabiner/assets/complex_modifications
   ```

2. Create symbolic links to the JSON files in your dotfiles:
   ```bash
   # Replace /path/to/your/dotfiles with your actual dotfiles path
   DOTFILES_PATH="/path/to/your/dotfiles"

   # Link all JSON files
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/japanese-input-toggle.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/spacebar-to-shift.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/vylet-alt-layout.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/shingeta/shingeta_en.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/shingeta/shingeta_jp.json" ~/.config/karabiner/assets/complex_modifications/
   ```

3. Restart Karabiner-Elements or go to Settings > Complex Modifications to see the new configurations.

4. Enable the desired rules in Karabiner-Elements Settings > Complex Modifications > Add rule.


**Note**: Karabiner-Elements only reads JSON files directly from the `complex_modifications` directory and does not recursively search subdirectories. The symbolic links allow you to keep your configurations organized in your dotfiles while making them available to Karabiner-Elements.

### Credits

These configurations are based on or include work from:
- **KE-complex_modifications** (Unlicense)
- **Shingeta Layout** by kouy and funatsufumiya (MIT License)
- **Vylet Keyboard Layout** by MightyAcas

See the LICENSE file for complete attribution information.

# Usage

## CLI (recommended)

All CLI commands automatically append:
`--override-input local "$FACTS"` and `--override-input secrets "$SECRETS"`.

Defaults:
- `FACTS_DIR=$HOME/.config/dotfiles-local`
- `SECRETS_DIR=$HOME/.config/dotfiles-secrets`
- `FACTS=path:$FACTS_DIR`
- `SECRETS=path:$SECRETS_DIR`

### Bootstrap (first run)
```bash
# Generate facts/secrets, run doctor, then optionally apply
nix run .#bootstrap -- --host a2m_mac --rice full --apply

# Non-interactive (auto-apply)
nix run .#bootstrap -- --host a2m_mac --rice full --yes
```

### Doctor (health checks)
```bash
# Basic checks
nix run .#doctor -- --host a2m_mac

# Strict checks (includes nix flake check)
nix run .#doctor -- --host a2m_mac --strict

# JSON output for CI
nix run .#doctor -- --json
```

### Apply (build/switch)
```bash
# Apply default rice
nix run .#apply -- --host a2m_mac

# Switch rices
nix run .#apply -- --host a2m_mac --rice minimum

# Build only (no switch)
nix run .#apply -- --host a2m_mac --action build

# Avoid sudo (CI/non-privileged)
nix run .#apply -- --host a2m_mac --no-sudo --action build

# Pass extra args to darwin-rebuild
nix run .#apply -- --host a2m_mac -- --show-trace
```

### Update (flake inputs + checks/build)
```bash
# Factory-style updates (flake inputs + nvfetcher + checks/build)
nix run .#update -- --host a2m_mac

# Update all inputs
UPDATE_ALL=1 nix run .#update -- --host a2m_mac

# Force checks + formatter
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host a2m_mac
```

External binaries tracked outside nixpkgs live in `nix/nvfetcher/sources.toml`.

## Manual commands (darwin-rebuild / home-manager)
```bash
# nix-darwin configuration
sudo darwin-rebuild switch --flake .#<PROFILE_NAME> \
  --override-input local path:$HOME/.config/dotfiles-local \
  --override-input secrets path:$HOME/.config/dotfiles-secrets

# home-manager configuration (replace <HOSTNAME> with your actual hostname)
nix run home-manager/release-25.05 -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$HOME/.config/dotfiles-local \
  --override-input secrets path:$HOME/.config/dotfiles-secrets
```

## Troubleshooting
- **`attribute 'darwinConfigurations' missing`** → Your local inputs are stubbed (or missing). Ensure `~/.config/dotfiles-local/facts.nix` exists and remove any `STUB` file, then rerun `nix run .#doctor`.
- **`target not found for host/rice`** → Run `nix run .#doctor -- --host <host> --rice <rice>` to see available targets.
- **`darwin-rebuild: command not found`** → `nix run .#apply` uses the nix-darwin wrapper automatically; for manual runs install it with `nix profile install github:nix-darwin/nix-darwin#darwin-rebuild`.
- **`error: unrecognised flag '--flake'`** → Ensure you invoke `nix run <flake>#<pkg> -- <cmd>`. Everything after `--` is passed through to `darwin-rebuild`.
- **Using `sudo`** → macOS resets `PATH` under `sudo`; use the CLI (which calls `sudo -E`) or run `sudo -E darwin-rebuild …`.
