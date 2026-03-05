## Flake templates

This repository publishes a web development template that you can use via Nix flakes:

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
```

It provides:
- Dev shell with Node.js 22, pnpm, bun, AWS CLI v2, jq/yq, mkcert, just (`wrangler` is optional and commented by default)
- Prettier formatting integrated via treefmt-nix and exposed as `apps.format`
- `nix run .#dev` for development tasks and `nix flake check` hooks

# dotfiles

## Prerequisites
- Nix(Lix or Determinate's vanilla)

## Profiles (Denix hosts/rices)

This flake uses [Denix](https://github.com/yunfachi/denix) with system-scoped trees:

- `nix/denix/darwin/{hosts,rices}`
- `nix/denix/nixos/{hosts,rices}`
- `nix/denix/home/{hosts,rices}`

- Hosts: `a2m_mac` (default rice: `full`), `mn_mac` (default rice: `full`).
- Rices: `base`, `darwin`, `dev`, `full`, `minimum`.
  - `base`: cross-platform essentials (`system.nix`, core CLI, shell, Git, GPG/SOPS).
  - `darwin`: macOS base integrations (Homebrew + hostnames/fonts).
  - `dev`: editor/terminal/workstation stack.
  - `full`: composition of `base + darwin + dev`.
  - `minimum`: minimal base profile alias.

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

When `--rice` is provided, the CLI resolves only `host-rice` (no implicit fallback to `host`).

Home Manager outputs are dedicated one-per-host profiles:
`<user>@a2m_mac`, `<user>@mn_mac`, `<user>@a2m_nixos`.

## Application Source Policy

Application/tool sourcing priority is:

- Detailed policy: [`docs/homebrew-policy.md`](docs/homebrew-policy.md)

1. `tools.system.homebrewNative` (nix-darwin managed Homebrew) for items that should stay "always latest".
2. `tools.system.brewNix` for pure-Nix/pinned/verified casks.
3. Custom implementation (for example `mk-node-cli-overlay`) only when both paths above are unsuitable.

## Terraform / OpenTofu Policy

1. Terraform/OpenTofu are managed per project via each repo's `flake.nix` (recommended default).
2. Dotfiles/Home Manager can also provide them through `myconfig.tools.dev` for convenience.
3. Unfree allow-list is derived from enabled tools (for example `terraform`, `vscode`) via helper wiring; `allowAll` remains disabled.
4. For Terraform-only repos, set `nixpkgs.config.allowUnfreePredicate` in that repo's flake and include `pkgs.terraform` in the devShell.

Example (`flake.nix` for a Terraform repo):

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs = { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.terraform pkgs.opentofu ];
      };
    };
}
```

## Tool Catalog (myconfig.tools)

List effective tool toggles for a target host/rice:

```bash
nix run .#list-tools -- --host a2m_mac
nix run .#list-tools -- --host a2m_mac --rice minimum --format json
```

Manual evaluation (JSON):

```bash
nix eval --json .#darwinConfigurations.a2m_mac-minimum.config.myconfig.tools
```

## VS Code Instances (Directory Profiles)

This repo uses "directory profiles" to run multiple isolated VS Code instances
(separate user-data + extensions dirs) without relying on macOS app-bundle hacks.

- Profiles live under `apps/vscode/<name>/`.
  - `_default/` provides the baseline.
  - Each profile can define:
    - `settings.json`
    - `extensions.txt`
    - `extensions-disabled.txt` (installed but always launched disabled)
    - `icon.icns` (optional, macOS launcher icon)
- Generated commands:
  - `code-<name>`: self-bootstraps (if baseline changed) then launches the instance.
  - `code-<name>-bootstrap`: seed/merge settings and install baseline extensions.
  - `code-<name>-reset`: backup the instance dir and re-bootstrap.

See `docs/vscode.md` for details.

## Terminal Compatibility

**For macOS users**: Please use a 24-bit True Color compatible terminal instead of the default Terminal.app. The Starship prompt configuration in this repository uses True Color (#RRGGBB) values that are only properly displayed in terminals with full color support.

**Recommended terminals:**
- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

**Why this matters**: macOS Terminal.app only supports 256-color palette, which causes the Starship prompt colors to be approximated and appear different from the intended design. True Color terminals can display the full 16.7 million color spectrum, ensuring consistent visual appearance.

### Terminal.app profile management (without AppleScript)

Terminal.app profiles are managed as `.terminal` files in this repo (`surfaces/terminal/desired/`), then imported during Home Manager activation.
Runtime sync operations are implemented through the shared sync adapter core (`nix/scripts/sync-core.sh`) with a Terminal adapter in `nix/scripts/terminal.sh`.
See `docs/reconciled-surfaces.md` for shared drift workflow and adapter contract.

- Source of truth: `surfaces/terminal/desired/*.terminal`
- Managed directory option: `tools.terminal.terminalApp.managedDir` (default: `surfaces/terminal/desired`)
- State guard: stores last-applied profile hashes under `~/.local/state/dotfiles/sync/terminal-app/profiles/*.sha256`
- Import behavior: when current hash matches last-applied, repo updates apply safely without `--force`
- Selection: `tools.terminal.terminalApp.defaultProfile` / `tools.terminal.terminalApp.startupProfile`
- Drift guard: apply aborts when current Terminal profile differs from last-applied (`tools.terminal.terminalApp.failOnDrift = true`)
- Force behavior: `tools.terminal.terminalApp.force = true` adds `--force` during activation apply

Current managed profiles:
- `Atalie Standard` (`surfaces/terminal/desired/Atalie-Standard.terminal`)
- `Atalie Dark` (`surfaces/terminal/desired/Atalie-Dark.terminal`)
- `Atalie Glass` (`surfaces/terminal/desired/Atalie-Glass.terminal`)
- `Atalie Glass Dark` (`surfaces/terminal/desired/Atalie-Glass-Dark.terminal`)
- `Atalie Glass Light` (`surfaces/terminal/desired/Atalie-Glass-Light.terminal`)

Current default profile:
- `Atalie Standard`

Drift handling workflow:

```bash
# 1) Check drift
nix run .#dotfiles -- terminal sync --check
# (returns non-zero when drift/missing/invalid profiles are detected)

# Optional: show concise per-profile diff details
nix run .#dotfiles -- terminal sync --check --diff

# 2) If drift is intentional, stage current Terminal.app values (does not overwrite repo)
nix run .#dotfiles -- terminal sync --adopt

# Optional: overwrite repo files directly (conflicts need --force)
nix run .#dotfiles -- terminal sync --adopt --in-place
nix run .#dotfiles -- terminal sync --adopt --in-place --force

# Optional: clear lastApplied state (all or one profile)
nix run .#dotfiles -- terminal sync --forget
nix run .#dotfiles -- terminal sync --forget --profile "Atalie Standard"

# 3) Apply from CLI (same reconciler used by activation)
nix run .#dotfiles -- terminal sync --apply

# 4) Use force only when you intentionally want to overwrite external edits
nix run .#dotfiles -- terminal sync --apply --force
```

### Shell sync (lastApplied 3-way)

Shell local overrides are managed with lastApplied state:
Runtime sync operations are implemented through the shared sync adapter core (`nix/scripts/sync-core.sh`) with a shell adapter in `nix/scripts/shell.sh`.

- Desired source:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
  - `surfaces/shell/desired/fish.config.block.fish`
  - `surfaces/shell/desired/00-dotfiles.fish`
- Local targets:
  - `~/.nix/.zshrc` (managed block only; runtime ZDOTDIR entrypoint)
  - `~/.bashrc` (managed block only; runtime bash entrypoint)
  - `~/.config/fish/config.fish` (managed block only; runtime fish entrypoint)
  - `~/.config/fish/conf.d/00-dotfiles.fish` (whole file)
- State guard: `~/.local/state/dotfiles/sync/shell/blocks/*.sha256`
- `shell sync` only manages declared targets; it does not mutate `~/.zshrc` directly.

Managed block markers:

```bash
# >>> dotfiles-managed:bashrc >>>
# ... managed content ...
# <<< dotfiles-managed:bashrc <<<

# >>> dotfiles-managed:fish.config >>>
# ... managed content ...
# <<< dotfiles-managed:fish.config <<<
```

Workflow:

```bash
# 1) Check drift/conflict
nix run .#dotfiles -- shell sync --check

# Optional: show diff for drifted targets
nix run .#dotfiles -- shell sync --check --diff

# 2) If local edits are intentional, stage adopt output
nix run .#dotfiles -- shell sync --adopt

# Optional: overwrite desired managed files directly (conflicts require --force)
nix run .#dotfiles -- shell sync --adopt --in-place
nix run .#dotfiles -- shell sync --adopt --in-place --force

# 3) Migrate legacy or invalid shell entrypoint shapes (explicit one-time step)
nix run .#dotfiles -- shell sync --migrate

# 4) Optional: clear lastApplied state
nix run .#dotfiles -- shell sync --forget
nix run .#dotfiles -- shell sync --forget --target zsh-zdotdir
nix run .#dotfiles -- shell sync --forget --target bash-rc
nix run .#dotfiles -- shell sync --forget --target fish-config
```

`nix run .#apply -- --host <host>` triggers shell reconciliation during Home Manager activation.
By default activation runs `shell sync --apply` (with drift/conflict failures), and can be tuned via:

- `tools.shell.sync.force = true` to pass `--force`
- `tools.shell.sync.failOnDrift = false` to run `shell sync --check --details` and continue on drift

Shell entrypoint writeability regression tests (isolated + auto cleanup):

```bash
nix/scripts/shell-zsh-writeability-test.sh
```

The test script uses temporary `HOME`/`XDG_STATE_HOME` and removes all test files on exit.

Additional sync adapter/core tests:

```bash
nix/scripts/sync-core-fake-adapter-test.sh
nix/scripts/sync-shell-smoke-test.sh
nix/scripts/sync-terminal-smoke-test.sh
nix/scripts/vscode-instances-smoke-test.sh
```

## Local Facts + Secrets (Override Inputs)

This repo no longer uses Git clean/smudge filters. Machine-specific facts and secrets live outside Git and are injected at build time using flake overrides.
Both inputs default to `~/.config/dotfiles/` (store `facts.nix` and `secrets.nix` side-by-side).

Default layout:
```
~/.config/dotfiles/
├── facts.nix
├── secrets.nix
├── .sops.yaml
└── files/
    └── ai.env.sops.yaml
```

### Facts (non-secret)

- Create `~/.config/dotfiles/facts.nix`
- Required: `user.username`
- Recommended (for Git identity): `user.fullName`, `user.email`
- Optional overrides:
  `user.homeDirectory` (auto-derived) and `user.platform` (defaults to `aarch64-darwin`; set explicitly on Intel Macs)

Example `facts.nix`:
```nix
{
  user = {
    username = "yourname";

    # Recommended (used by Git module)
    fullName = "Your Name";
    email = "you@example.com";

    # Optional overrides
    # homeDirectory = "/Users/yourname";
    # platform = "x86_64-darwin"; # default is aarch64-darwin

    stateVersion = {
      home = "25.05";
      darwin = 6;
    };
  };

  machines = {
    a2m_mac = {
      computerName = "Your Mac";
      localHostName = "your-mac";
      hostName = "your-mac";
    };
  };
}
```

These machine values are used to set macOS system naming via `tools.system.hostnames`.

### Secrets (confidential)

- Create `~/.config/dotfiles/secrets.nix`
- Store encrypted files under `~/.config/dotfiles/files/` (sops+age recommended)
- Define `secrets.nix` and encrypted files (sops+age recommended)
- Detailed setup notes: [`docs/secrets-local.md`](docs/secrets-local.md)

Example `secrets.nix`:
```nix
{
  files = {
    aiEnv = {
      sopsFile = ./files/ai.env.sops.yaml;
      targetPath = ".config/dotfiles/ai.env";
      mode = "0600";
    };
  };
}
```

Optional shell sourcing (in `~/.zshrc`):
```bash
if [ -f "$HOME/.config/dotfiles/ai.env" ]; then
  source "$HOME/.config/dotfiles/ai.env"
fi
```

### Build with overrides

All `nix run .#apply|.#update|.#doctor|.#bootstrap` commands pass overrides automatically. Manual invocations still need them:

```bash
darwin-rebuild build --flake .#a2m_mac \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles
```

**Note**: `nix/local/` and `nix/secrets/` in the repo are stubs for public evaluation (templates only). Real configurations require `--override-input` and should not include a `STUB` file.

## Binary Cache (Cachix / Attic)

This repo can pull from extra binary caches via your local facts.

Add to `~/.config/dotfiles/facts.nix`:
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

## Flake Config Trust (`accept-flake-config`)

This repo defaults `system.nix.acceptFlakeConfig = true` for convenience, so flake-level `nixConfig` is applied automatically.

Tradeoff:
- Pros: smoother day-to-day usage for this dotfiles flake (fewer manual flags).
- Cons: evaluating unknown third-party flakes can apply their `nixConfig` (for example cache/substituter settings).

If you want stricter behavior, disable it in your host/rice config:

```nix
{
  myconfig.system.nix.acceptFlakeConfig = false;
}
```

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
- `FACTS_DIR=$HOME/.config/dotfiles`
- `SECRETS_DIR=$HOME/.config/dotfiles`
- `FACTS=path:$FACTS_DIR`
- `SECRETS=path:$SECRETS_DIR`

### Bootstrap (first run)
```bash
# Generate minimal facts/secrets, run doctor, then optionally apply
nix run .#bootstrap -- --host a2m_mac --rice full --apply

# Non-interactive (auto-apply)
nix run .#bootstrap -- --host a2m_mac --rice full --yes
```

`bootstrap` creates a minimal `facts.nix` (`user.username` only) and leaves extra fields as opt-in comments.

### Doctor (health checks)
```bash
# Basic checks
nix run .#doctor -- --host a2m_mac

# Strict checks (includes nix flake check + enabled sync drift checks)
nix run .#doctor -- --host a2m_mac --strict

# JSON output for CI
nix run .#doctor -- --json
```

For strict sync drift checks, pass `--host` so `doctor` can gate checks by target tool enablement.

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
# Factory-style updates (flake inputs + checks/build)
nix run .#update -- --host a2m_mac

# Update all inputs
UPDATE_ALL=1 nix run .#update -- --host a2m_mac

# Force checks + formatter
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host a2m_mac
```

### Formatter / Checks / Dev Shell
```bash
# treefmt formatter (used by `nix fmt`)
nix fmt

# explicit format app (same formatter as above)
nix run .#format

# checks: treefmt + statix + deadnix + shellcheck
nix flake check \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles

# dotfiles development toolchain
nix develop
```

## Manual commands (darwin-rebuild / home-manager)
```bash
# nix-darwin configuration
sudo darwin-rebuild switch --flake .#<PROFILE_NAME> \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles

# home-manager configuration (replace <HOSTNAME> with your actual hostname)
nix run home-manager/release-25.05 -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles
```

## Troubleshooting
- **`attribute 'darwinConfigurations' missing`** → Your local inputs are stubbed (or missing). Ensure `~/.config/dotfiles/facts.nix` exists and remove any `STUB` file, then rerun `nix run .#doctor`.
- **`target not found for host/rice`** → Run `nix run .#doctor -- --host <host> --rice <rice>` to see available targets.
- **`darwin-rebuild: command not found`** → `nix run .#apply` uses the nix-darwin wrapper automatically; for manual runs install it with `nix profile install github:nix-darwin/nix-darwin#darwin-rebuild`.
- **`error: unrecognised flag '--flake'`** → Ensure you invoke `nix run <flake>#<pkg> -- <cmd>`. Everything after `--` is passed through to `darwin-rebuild`.
- **Using `sudo`** → macOS resets `PATH` under `sudo`; use the CLI (which calls `sudo -E`) or run `sudo -E darwin-rebuild …`.
