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

Shared modules, catalogs, and operational scripts now live outside the Denix host trees:

- `nix/modules/{shared,tools}`
- `nix/catalog/tools/{nixpkgs.nix,homebrew.nix}`
- `scripts/` for shell entrypoints, helpers, adapters, and smoke tests
- `nix/scripts/` for Nix expressions used by the CLI

See [`docs/architecture.md`](docs/architecture.md) for the current responsibility split.

Operational note: this repo keeps shared NixOS and standalone Home Manager trees, but the day-to-day CLI in this flake (`apply`, `update`, `list-tools`, and target-aware `doctor`) is Darwin-first and resolves `darwinConfigurations`.
`nixosConfigurations` and `homeConfigurations` remain available as auxiliary outputs for manual evaluation and targeted experiments; the operational CLI does not resolve them.

- Hosts: `a2m_mac` (default rice: `full`), `mn_mac` (default rice: `full`).
- Rices: `base`, `darwin`, `dev`, `full`, `minimum`.
  - `base`: shared essentials (`system.nix`, core CLI, shell, Git, GPG/SOPS).
  - `darwin`: macOS base integrations (Homebrew + hostnames/fonts).
  - `dev`: editor/terminal/workstation stack.
  - `full`: composition of `base + darwin + dev`.
  - `minimum`: minimal base profile alias.

CLI usage examples (recommended for macOS / nix-darwin):

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

1. Use Nix packages by default for CLI tools and libraries.
2. Use Homebrew for macOS-specific or intentionally latest-first software, preferably through catalog-backed `myconfig.tools` toggles.
3. Use `tools.system.brewNix` only when native Homebrew integration is the wrong fit and a pinned cask path is needed.
4. Direct `tools.system.homebrewNative.{brews,casks,masApps}` edits are for module internals; `flake check` validates the final Homebrew ownership set.

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

Group toggles such as `tools.dev.enable` are bundle switches, not just namespaces. Enabling a group fans out to the catalog-owned tool toggles under that group.
Use `list-tools` as the canonical way to inspect the expanded toggle set for a host/rice, and see [`docs/tool-catalog.md`](docs/tool-catalog.md) for the catalog rules.

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
- Runtime boundary:
  - Settings, launchers, baseline extension lists, and icons are repo-managed.
  - Installed extensions remain intentionally mutable (`mutableExtensionsDir = true`); bootstrap adds missing baseline extensions but does not remove user-added ones.

See `docs/vscode.md` for details.

## Mutable Editor Tooling

- Emacs app/config wiring is declarative, but package installation still happens through `package.el` against GNU ELPA / NonGNU ELPA / MELPA at runtime.
- VS Code instance definitions are declarative, but extension state is intentionally mutable as described above.
- This repo treats those editor runtimes as a convenience boundary: config is pinned here, packages/extensions are not.

## Terminal Compatibility

Any modern terminal works with the current Zsh setup. Terminal.app profile sync has been removed from this repo, so Terminal.app is just an unmanaged fallback.

**Recommended terminals:**

- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

## Zsh Stack

The default Zsh prompt is Pure. `base` / `minimum` keep that prompt-only setup, while `dev` / `full` also enable:

- `fzf` keybindings: `CTRL-T` for file insert, `ALT-C` for directory jump
- `fzf-tab` on `TAB`
- `Atuin` on `CTRL-R`
- `zoxide` via `z` and `zi`
- `direnv` + `nix-direnv`
- `delta` for Git paging

### Shell sync (writable entrypoints)

Shell sync is a small, stateless writable-entrypoint manager.
Runtime sync operations are implemented through `scripts/sync.sh` (surface: `shell`) with `scripts/sync-adapters/shell.sh`.
Its job is to keep writable shell entrypoints in place and update only repo-managed blocks/files.
Shared shell helpers are shipped separately as `apps/shell/common.sh` and linked to `~/.config/shell/common.sh`; they are declarative Home Manager content, not part of runtime sync state.

- Desired source:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
- Local targets:
  - `~/.nix/.zshrc` (managed block only; runtime ZDOTDIR entrypoint)
  - `~/.bashrc` (managed block only; runtime bash entrypoint)
- Local extension points:
  - zsh: `~/.config/shell/zsh.local.sh`
  - bash: `~/.config/shell/bash.local.sh`
- `sync shell` manages only the declared targets above.
- `sync shell --apply` automatically normalizes common entrypoint shapes:
  - missing files
  - writable regular files
  - `/nix/store/...` symlinks
  - readable non-store symlinks, which are materialized back into writable regular files
- Content outside the managed markers is preserved.
- Shell sync does not keep machine-local `lastApplied` state and does not adopt local changes back into the repo.
- Managed macOS login-shell switching supports `zsh` and `bash`.

Opt-in zsh root compatibility:

- Runtime zsh still uses `~/.nix/.zshrc`.
- If you enable `tools.shell.zsh.rootZshrcCompat.enable = true`, activation keeps `~/.zshrc` as a symlink to `.nix/.zshrc`.
- This is for installers that append to `~/.zshrc`; the write lands in the writable runtime wrapper.
- Existing regular-file `~/.zshrc` is never overwritten automatically.
- If you need to migrate an existing regular-file `~/.zshrc`, use `bash scripts/zshrc-compat.sh --migrate`.

Managed block markers:

```bash
# >>> dotfiles-managed:bashrc >>>
# ... managed content ...
# <<< dotfiles-managed:bashrc <<<
```

Workflow:

```bash
# 1) Check whether any target needs apply
nix run .#dotfiles -- sync shell --check

# Optional: show details or a managed-content diff
nix run .#dotfiles -- sync shell --check --details
nix run .#dotfiles -- sync shell --check --details --diff

# 2) Repair or create writable entrypoints in place
nix run .#dotfiles -- sync shell --apply

# Optional: restrict to one shell group or one target
nix run .#dotfiles -- sync shell --apply --group zsh
nix run .#dotfiles -- sync shell --check --item bash-rc

# Optional: inspect or repair the ~/.zshrc compat symlink when enabled
bash scripts/zshrc-compat.sh --check
bash scripts/zshrc-compat.sh --migrate
```

Legacy CLI migration:

| Old command                            | New command                            |
| -------------------------------------- | -------------------------------------- |
| `nix run .#dotfiles -- shell sync ...` | `nix run .#dotfiles -- sync shell ...` |
| `--target <id>`                        | `--item <id>`                          |
| `--shell <name>`                       | `--group <name>`                       |

`nix run .#apply -- --host <host>` triggers shell reconciliation during Home Manager activation by running `sync shell --apply` for the enabled shell groups.
If `tools.shell.zsh.rootZshrcCompat.enable = true`, activation also runs `bash scripts/zshrc-compat.sh --apply`.

Shell entrypoint writeability regression tests (isolated + auto cleanup):

```bash
scripts/tests/shell-zsh-writeability-test.sh
scripts/tests/zshrc-compat-test.sh
```

These test scripts use a temporary `HOME` and remove all test files on exit.

Additional sync tests:

```bash
scripts/tests/sync-cli-migration-test.sh
scripts/tests/sync-cli-common-parse-test.sh
scripts/tests/sync-shell-smoke-test.sh
scripts/tests/vscode-instances-smoke-test.sh
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
  `user.homeDirectory` (auto-derived) and `machines.<host>.platform` (per-host override when you truly need it).
- Recommended: keep `user.platform` explicit. `bootstrap` auto-detects it and writes `aarch64-darwin` on Apple Silicon Macs.

Example `facts.nix`:

```nix
{
  user = {
    username = "yourname";
    platform = "aarch64-darwin";

    # Recommended (used by Git module)
    fullName = "Your Name";
    email = "you@example.com";

    # Optional overrides
    # homeDirectory = "/Users/yourname";

    stateVersion = {
      home = "25.05";
      darwin = 6;
      nixos = "25.05";
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

Optional shell sourcing:

- zsh: `~/.config/shell/zsh.local.sh`
- bash: `~/.config/shell/bash.local.sh`

Example (`~/.config/shell/zsh.local.sh`):

```bash
if [ -f "$HOME/.config/dotfiles/ai.env" ]; then
  source "$HOME/.config/dotfiles/ai.env"
fi
```

### Build with overrides

All `nix run .#apply|.#update|.#doctor|.#bootstrap|.#list-tools` commands derive `FACTS` and `SECRETS` from `FACTS_DIR` and `SECRETS_DIR` automatically. Manual invocations still need explicit overrides:

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- build --flake .#a2m_mac \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```

`nix run .#darwin-rebuild -- ...` uses the nix-darwin wrapper pinned by this repo's `flake.lock`.

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

If you're using this dotfiles repository with Nix and home-manager, the Karabiner-Elements configurations are set up declaratively through symbolic links.

The configuration is managed in `nix/modules/tools/system/karabiner.nix` and will automatically:

1. Create the necessary directories
2. Generate symbolic links for the managed rule files and `karabiner.json`
3. Keep the links updated when you rebuild your configuration

**Configuration Details:**

- Configuration files are sourced from the `keyboards/` directory in this repo
- The linked complex-modification set comes from the explicit `ruleFiles` list in the module
- The setup is declarative and version-controlled
- Changes take effect after running `nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME>`

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

These operational CLI commands are Darwin-first: they target `darwinConfigurations` and macOS-specific checks/builds.
`apply`, `update`, `list-tools`, and `bootstrap` require `--host`, a positional host, or `HOST=...`.

Defaults:

- `FACTS_DIR=$HOME/.config/dotfiles`
- `SECRETS_DIR=$HOME/.config/dotfiles`
- `FACTS=path:$FACTS_DIR`
- `SECRETS=path:$SECRETS_DIR`

Advanced overrides:

- `FACTS` and `SECRETS` may point to other flake input references when needed.
- `doctor` and `bootstrap` still require matching `FACTS_DIR` / `SECRETS_DIR` when those overrides are not `path:...`, because they read or write local files directly.

### Bootstrap (first run)

```bash
# Generate minimal facts/secrets, run doctor, then optionally apply
nix run .#bootstrap -- --host a2m_mac --rice full --apply

# Non-interactive (auto-apply)
nix run .#bootstrap -- --host a2m_mac --rice full --yes
```

`bootstrap` creates a minimal `facts.nix` (`user.username` only) and leaves extra fields such as `stateVersion` as opt-in comments.

### Doctor (health checks)

```bash
# Global facts/secrets/basic system checks
nix run .#doctor

# Basic checks
nix run .#doctor -- --host a2m_mac

# Strict checks (includes nix flake check + enabled sync checks)
nix run .#doctor -- --host a2m_mac --strict

# JSON output for CI
nix run .#doctor -- --json
```

`doctor` can run without a host for global facts/secrets/basic system checks.
For target evaluation and strict sync checks, pass `--host` so `doctor` can gate checks by target tool enablement.

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
# Update all non-path root inputs from flake.lock, then run checks/build
nix run .#update -- --host a2m_mac

# Full `nix flake update`
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
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR

# home-manager configuration (replace <HOSTNAME> with your actual hostname)
nix run home-manager/release-25.05 -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```

## Troubleshooting

- **`attribute 'darwinConfigurations' missing`** → Your local inputs are stubbed (or missing). Ensure `~/.config/dotfiles/facts.nix` exists and remove any `STUB` file, then rerun `nix run .#doctor`.
- **`target not found for host/rice`** → Run `nix run .#doctor -- --host <host> --rice <rice>` to see available targets.
- **`FACTS_DIR is required ...` / `SECRETS_DIR is required ...`** → `doctor` and `bootstrap` need local file paths. If you override `FACTS` or `SECRETS` with a non-`path:` ref, also set the matching `*_DIR` variable.
- **`darwin-rebuild: command not found`** → Use `nix run .#darwin-rebuild -- ...` for manual runs; `nix run .#apply` and `nix run .#update` already use the pinned wrapper automatically.
- **`error: unrecognised flag '--flake'`** → Ensure you invoke `nix run <flake>#<pkg> -- <cmd>`. Everything after `--` is passed through to `darwin-rebuild`.
- **Using `sudo`** → macOS resets `PATH` under `sudo`; use the CLI (which calls `sudo -E`) or the pinned wrapper via `nix run .#darwin-rebuild -- ...`.
