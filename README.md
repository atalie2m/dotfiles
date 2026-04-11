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

This flake uses [Denix](https://github.com/yunfachi/denix) with Darwin-only host/rice trees:

- `nix/denix/darwin/{hosts,rices}`

Shared modules, catalogs, and operational scripts now live outside the Denix host trees:

- `nix/modules/{shared,tools}`
- `nix/catalog/tools/{nixpkgs.nix,homebrew-ownership.nix}`
- `scripts/` for thin shell entrypoints and smoke tests
- `nix/scripts/` for Nix expressions used by the CLI

See [`docs/architecture.md`](docs/architecture.md) for the current responsibility split.
See [`docs/architecture-reset.md`](docs/architecture-reset.md) for the reset rationale, before/after changes, and design intent.

Operational note: the supported root flake API is Darwin-first and exposes `darwinConfigurations` plus `templates.web-dev`.

- Hosts: `pro_mac` (default rice: `pro`), `ultra_mac` (default rice: `ultra`), `minimal_mac` (default rice: `base`).
- Rices: `base`, `darwin`, `dev`, `pro`, `ultra`, `partial`.
  - `base`: shared essentials (`system.nix`, core CLI, shell, Git, GPG/SOPS).
  - `darwin`: macOS base integrations (Homebrew + hostnames/fonts).
  - `dev`: editor/terminal/workstation stack.
  - `pro`: composition of `base + darwin + dev` without VS Code.
  - `ultra`: complete profile (`base + darwin + dev`).
  - `partial`: composition of `base + darwin + dev` with targeted overrides (only `codex` enabled among AI coding agents, VS Code installed but activation sync off).

Canonical host names and CLI examples live in [`docs/commands.md`](docs/commands.md).

Manual attribute examples (still valid):
`pro_mac`, `ultra_mac`, `minimal_mac`, `ultra_mac-base`, `minimal_mac-ultra`, `pro_mac-partial`.

When `--rice` is provided, the CLI resolves only `host-rice` (no implicit fallback to `host`).

## Application Source Policy

Application/tool sourcing priority is:

- Detailed policy: [`docs/homebrew-policy.md`](docs/homebrew-policy.md)

1. Use Nix packages by default for CLI tools and libraries.
2. Use Homebrew for macOS-specific or intentionally latest-first software, preferably through catalog-backed `myconfig.tools` toggles.
3. Use `tools.system.brewNix` only when native Homebrew integration is the wrong fit and a pinned cask path is needed.
4. Homebrew backend lists are internal implementation detail; `flake check` validates the unified ownership registry, duplicate item claims, cross-source overlaps, and unregistered items.

`Claude Code` is intentionally an exception: this repo does not install it via Homebrew.
Enablement under `tools.aiCodingAgent.claudeCode` prepares the native install path
surface (`~/.local/bin`) and lets `nix run .#apply` remind you when the upstream
native install is missing or shadowed by another launcher. Install/update steps
should come from <https://code.claude.com/docs/en/quickstart>; after installing,
run `nix run .#apply -- --host <host>`, then refresh with `exec zsh -l` so the
managed PATH picks up `~/.local/bin`.

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
Use `list-tools` for single host/rice inspection and `matrix-tools` for cross-target matrices. `matrix-tools` shows group-level toggles by default and can expand to deeper toggles with `--full`; see [`docs/tool-catalog.md`](docs/tool-catalog.md) for catalog scope and [`docs/commands.md`](docs/commands.md) for CLI examples.

Manual evaluation (JSON):

```bash
nix eval --json .#darwinConfigurations.ultra_mac-base.config.myconfig.tools
```

## VS Code Profiles

This repo now uses a single VS Code installation with native VS Code profiles.
The declarative source stays under `apps/vscode/<name>/`, and runtime materialization happens through `sync vscode`.

- `apps/vscode/_default/` is the shared layer applied to every managed profile.
- `apps/vscode/native/` is managed as a native profile (`Native`).
- `apps/vscode/<name>/` for any other name maps to a native custom profile with that display name.
- Supported inputs are `settings.json`, `extensions.txt`, and bootstrap-only `default-disabled-extensions.txt`.
- VS Code application installation is unmanaged by Nix; install Visual Studio Code.app separately (or provide `VSCODE_CODE_BIN`).
- `sync vscode` uses the Rust engine (`dotfiles-sync-vscode`).
- **Ultra rice only:** stock Darwin bundles enable the VS Code module and run `sync vscode --apply` during Home Manager activation (`tools.editor.vscode.enable` and `tools.editor.vscode.sync.enable`). Other stock rices do not; run `nix run .#dotfiles -- sync vscode --apply` manually if you want the same behavior elsewhere.
- **Extension bulk install:** repo-owned extension IDs live under `apps/vscode/` — chiefly `_default/extensions.txt` plus each profile's `extensions.txt` (for example `web/`, `native/`). That directory is the source of truth for what sync installs or uninstalls.
- `sync vscode --apply` reconciles fully repo-owned managed profile settings plus those repo-owned extensions into writable VS Code profile state when the toggles above are true (or whenever you invoke the CLI).
- `default-disabled-extensions.txt` is seeded once into the profile's extension enablement state; users can later enable those extensions in the VS Code UI and sync will not force them back off.
- Drift management is mutable by design: managed profile settings are fully repo-owned, while repo-owned extensions converge without adopting user-added extensions.

See `docs/vscode.md` for the runtime model and CLI.
See [`docs/reconciled-surfaces.md`](docs/reconciled-surfaces.md) for mutable vs immutable boundary details across shell, VS Code, and system app surfaces.

## Mutable Editor Tooling

- Emacs app/config wiring and package installation are Nix-first; repo-owned Elisp packages are pinned through Nix, while `use-package` declarations can still install missing packages at runtime when explicitly configured to do so.
- Neovim app/config wiring is declarative under `apps/neovim/`, while plugin installation/update happens at runtime through `lazy.nvim` using the repo-owned `lazy-lock.json`.
- VS Code profile definitions are declarative, but runtime state stays writable; managed profile settings are fully repo-owned and manual settings changes are overwritten on apply, while user-added extensions remain outside repo ownership.
- This repo treats those editor runtimes as a convenience boundary: config is pinned here, package/login/UI state is not.

## Terminal Compatibility

Any modern terminal works with the current Zsh setup. Terminal.app profile sync has been removed from this repo, so Terminal.app is just an unmanaged fallback.

**Recommended terminals:**

- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

## Zsh Stack

The default Zsh prompt is Pure. `base` keeps that prompt-only setup, while `dev` / `pro` / `ultra` also enable:

- `fzf` keybindings: `CTRL-T` for file insert, `ALT-C` for directory jump
- `fzf-tab` on `TAB`
- `Atuin` on `CTRL-R`
- `zoxide` via `z` and `zi`
- `direnv` + `nix-direnv`
- `delta` for Git paging

### Shell sync (writable entrypoints)

Shell sync is a small, stateless writable-entrypoint manager.
Runtime sync operations are implemented through `nix run .#dotfiles -- sync shell`; `scripts/sync.sh` is only a thin shell wrapper over the Rust `dotfiles` CLI.
Its job is to keep writable shell entrypoints in place and update only repo-managed blocks/files.
Shared shell helpers are shipped separately as `apps/shell/common.sh` and linked to `~/.config/shell/common.sh`; the repo's `scripts/` directory is also added to `PATH` when shell tooling is enabled. Both are declarative Home Manager content, not part of runtime sync state.

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

```

`nix run .#apply -- --host <host>` triggers shell reconciliation during Home Manager activation by running `sync shell --apply` for the enabled shell groups.

Shell entrypoint writeability regression tests (isolated + auto cleanup):

```bash
scripts/tests/shell-zsh-writeability-test.sh
```

These test scripts use a temporary `HOME` and remove all test files on exit.

Additional sync tests:

```bash
scripts/tests/sync-cli-common-parse-test.sh
scripts/tests/sync-shell-smoke-test.sh
scripts/tests/sync-vscode-smoke-test.sh
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
- Optional overrides: `user.homeDirectory` (auto-derived) and `machines.<host>.homeDirectory` (per-host override when you truly need it).
- Platform is no longer a raw facts input. Host declarations own `system`, and modules derive `os`/`arch` from `myconfig.hostContext`.

Example `facts.nix`:

```nix
{
  user = {
    username = "yourname";

    # Recommended (used by Git module)
    fullName = "Your Name";
    email = "you@example.com";

    # Optional overrides
    # homeDirectory = "/path/to/home/yourname";

    stateVersion = {
      home = "25.11";
      darwin = 6;
    };
  };

  machines = {
    ultra_mac = {
      computerName = "Your Mac";
      localHostName = "your-mac";
      hostName = "your-mac";
    };

    # Optional if you also use the pro_mac target:
    # pro_mac = {
    #   computerName = "Your Mac";
    #   localHostName = "your-mac";
    #   hostName = "your-mac";
    # };
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

All `nix run .#apply|.#update|.#doctor|.#bootstrap|.#list-tools|.#matrix-tools` commands derive `FACTS` and `SECRETS` from `FACTS_DIR` and `SECRETS_DIR` automatically. Manual invocations still need explicit overrides:

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- build --flake .#ultra_mac \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```

`nix run .#darwin-rebuild -- ...` uses the nix-darwin wrapper pinned by this repo's `flake.lock`.

**Note**: The repo ships placeholder public inputs under `nix/local/` and `nix/secrets/` so `darwinConfigurations` always evaluates. Real machines should still override both inputs with `~/.config/dotfiles/`.

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

Once set, the macOS CI job evaluates every `darwinConfigurations` target and builds the default host targets before pushing results to the cache.

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
`apply` and `list-tools` require `--host`, a positional host, or `HOST=...`.
`matrix-tools` evaluates all available `darwinConfigurations` and does not require `--host`.
`update` only requires a host when build is enabled (the default).
`bootstrap` only requires a host when `--apply` or `--yes` is used.

Defaults:

- `FACTS_DIR=$HOME/.config/dotfiles`
- `SECRETS_DIR=$HOME/.config/dotfiles`
- `FACTS=path:$FACTS_DIR`
- `SECRETS=path:$SECRETS_DIR`

Advanced overrides:

- `FACTS` and `SECRETS` may point to other flake input references when needed.
- `doctor` and `bootstrap` still require matching `FACTS_DIR` / `SECRETS_DIR` when those overrides are not `path:...`, because they read or write local files directly.

Canonical command examples live in [`docs/commands.md`](docs/commands.md).

### Bootstrap (first run)

`bootstrap` creates a minimal `facts.nix` with required `user.username`, optional identity fields, and commented optional machine/stateVersion examples.

### Doctor (health checks)

`doctor` can run without a host for global facts/secrets/basic system checks.
For target evaluation and strict sync checks, pass `--host` so `doctor` can gate checks by target tool enablement.

### Apply (build/switch)

### Update (flake inputs + checks/build)

### Formatter / Checks / Dev Shell

### Clean export

`export-clean` is tracked-only and requires Git to access a trusted worktree. It fails closed if Git is unavailable or refuses the repository; see [`docs/commands.md`](docs/commands.md) for examples.

## Manual commands (darwin-rebuild)

Manual rebuild examples live in [`docs/commands.md`](docs/commands.md).

## Troubleshooting

- **`no darwinConfigurations found` / `unable to evaluate darwinConfigurations`** → Verify your overridden `facts.nix` and `secrets.nix`, then rerun `nix run .#doctor`.
- **`target not found for host/rice`** → Run `nix run .#doctor -- --host <host> --rice <rice>` to see available targets.
- **`FACTS_DIR is required ...` / `SECRETS_DIR is required ...`** → `doctor` and `bootstrap` need local file paths. If you override `FACTS` or `SECRETS` with a non-`path:` ref, also set the matching `*_DIR` variable.
- **`darwin-rebuild: command not found`** → Use `nix run .#darwin-rebuild -- ...` for manual runs; `nix run .#apply` and `nix run .#update` already use the pinned wrapper automatically.
- **`error: unrecognised flag '--flake'`** → Ensure you invoke `nix run <flake>#<pkg> -- <cmd>`. Everything after `--` is passed through to `darwin-rebuild`.
- **Using `sudo`** → macOS resets `PATH` under `sudo`; `nix run .#apply` preserves `PATH` plus the dotfiles input override variables it needs, while manual runs should use the pinned wrapper via `nix run .#darwin-rebuild -- ...`.
