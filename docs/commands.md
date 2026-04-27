[日本語版はこちら](ja/commands.md)

# Commands

Canonical command examples and current host names live here. Keep README and AI helper files aligned to this page instead of duplicating command surfaces elsewhere.

## Current hosts and packages

- Hosts: `own_mac` (default profile: `pro`), `work_mac` (default profile: `pro`)
- Profiles: `minimal`, `lite`, `pro`, `ultra`
- Example darwin targets: `own_mac`, `own_mac-minimal`, `own_mac-lite`, `own_mac-ultra`, `work_mac`, `work_mac-minimal`, `work_mac-lite`, `work_mac-ultra`
- Packages: `dotfiles`, `dotfiles-cli`, `dotfiles-sync-vscode`
- Templates: `web-dev`, `rust-dev`, `go-dev`, `python-research`, `data-pipeline`, `native-dev`, `embedded-dev`, `apple-dev`, `infra-nixos`, `infra-iac`, `kubernetes-dev`, `container-oci`, `model-hf`, `docs-dev`, `api-db`, `ai-coding`, `release-dev`

## Project templates

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
nix flake init -t github:atalie2m/dotfiles#rust-dev
nix flake init -t github:atalie2m/dotfiles#infra-iac
nix flake init -t github:atalie2m/dotfiles#python-research
```

## Operational CLI

These commands are Darwin-only and resolve `darwinConfigurations`.
`work_mac` applies its host policy after the selected profile and host overrides, so `--profile ultra` is still capped by the work boundary.

```bash
# Apply default profile for each host
nix run .#apply -- --host own_mac
nix run .#apply -- --host work_mac

# Build only
nix run .#apply -- --host own_mac --action build

# Switch profiles explicitly
nix run .#apply -- --host own_mac --profile ultra
nix run .#apply -- --host work_mac --profile lite
nix run .#apply -- --host work_mac --profile ultra
nix run .#apply -- --host own_mac --profile minimal

# Inspect effective group/tool toggles
nix run .#list-tools -- --host own_mac
nix run .#list-tools -- --host work_mac --profile ultra --format json

# Inspect cross-target toggle matrix
nix run .#matrix-tools
nix run .#matrix-tools -- --format json
nix run .#matrix-tools -- --full --format json

# Bootstrap local inputs
nix run .#bootstrap
nix run .#bootstrap -- --host own_mac --apply
nix run .#bootstrap -- --host own_mac --yes

# Health checks
nix run .#doctor
nix run .#doctor -- --host own_mac
nix run .#doctor -- --host work_mac --strict
nix run .#doctor -- --json

# Update flake inputs and run checks/builds
UPDATE_SKIP_BUILD=1 nix run .#update
nix run .#update -- --host own_mac
UPDATE_ALL=1 nix run .#update -- --host own_mac
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host own_mac
```

## Runtime sync

```bash
# Shell entrypoints
nix run .#dotfiles -- sync shell --check
nix run .#dotfiles -- sync shell --check --details --diff
nix run .#dotfiles -- sync shell --apply

# Doom Emacs config
nix run .#dotfiles -- sync emacs --check
nix run .#dotfiles -- sync emacs --check --details --diff
nix run .#dotfiles -- sync emacs --apply
nix run .#dotfiles -- sync emacs --apply --bootstrap
nix run .#dotfiles -- sync emacs --check --config-only
nix run .#dotfiles -- sync emacs --adopt --item config

# Neovim config and Lazy lock state
nix run .#dotfiles -- sync neovim --check
nix run .#dotfiles -- sync neovim --check --details --diff
nix run .#dotfiles -- sync neovim --apply
nix run .#dotfiles -- sync neovim --adopt

# VS Code native profiles
nix run .#dotfiles -- sync vscode --check
nix run .#dotfiles -- sync vscode --check --details --diff
nix run .#dotfiles -- sync vscode --apply
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native
```

## Doom Emacs

`tools.editor.emacs.enable = true` installs the GUI Emacs app through Homebrew, installs the Doom/Meow sync tooling, and keeps `doom-meow` available under `~/.config/doom/modules/editor/meow`. Doom config files are writable runtime state reconciled by `sync emacs`; plain `sync emacs --check` and `sync emacs --apply` also verify that `${EMACSDIR:-~/.emacs.d}/bin/doom` is executable. Use `--config-only` only for tests or maintenance that intentionally reconciles the three config files without checking Doom runtime readiness.

`sync emacs --apply --bootstrap` first writes `~/.config/doom/{init,packages,config}.el` from the repo, then installs Doom when `${EMACSDIR:-~/.emacs.d}/bin/doom` is missing or runs `doom sync` when it is already present. If `${EMACSDIR:-~/.emacs.d}` exists but is not a Doom checkout, the bootstrapper moves it to a timestamped `.pre-doom.*` backup before cloning Doom.

`tools.editor.emacs.bootstrap.enable = true` keeps the activation-time `dotfiles-doom bootstrap` path, backed by the same CLI behavior. The `ultra` profile enables both `tools.editor.emacs.sync.enable` and `tools.editor.emacs.bootstrap.enable`; `pro` installs Emacs without setup.

```bash
dotfiles-doom bootstrap
dotfiles-doom sync
dotfiles-doom doctor
```

## Neovim and Goneovim

`tools.editor.neovim.enable = true` installs Neovim. `tools.editor.neovim.sync.enable = true` wires the repo-managed LazyVim config from `apps/neovim/`; `ultra` enables that setup and `pro` leaves it disabled. `tools.editor.goneovim.enable = true` installs the Goneovim GUI from the upstream Darwin release. This deliberately avoids the Homebrew cask because that cask depends on Homebrew `neovim`, is marked deprecated for macOS Gatekeeper validation, and is scheduled for disablement on 2026-09-01.

## Runtime overrides

- `HOME` is required for `nix run .#dotfiles -- sync shell ...`, `nix run .#dotfiles -- sync emacs ...`, `nix run .#dotfiles -- sync neovim ...`, and `nix run .#dotfiles -- sync vscode ...`, and it is also required whenever a command needs repo-default user-scoped paths.
- `DOTFILES_ROOT` overrides flake-root discovery for the Rust CLI and shell wrappers.
- `DOTFILES_PROFILE_DIRS` prepends colon-separated profile directories to shell profile discovery before `/etc/profiles/per-user/$USER` and `$HOME/.nix-profile`.
- `DOOMDIR` overrides the runtime Doom config directory for `sync emacs`; otherwise it defaults to `~/.config/doom`. Use `--doom-dir` for one command.
- `EMACSDIR` overrides the Doom checkout directory for `sync emacs`; otherwise it defaults to `~/.emacs.d`. Use `--emacs-dir` for one command.
- `FACTS_DIR` / `SECRETS_DIR` default to `~/.config/dotfiles`; `FACTS` / `SECRETS` default to `path:$FACTS_DIR` / `path:$SECRETS_DIR`.
- `DARWIN_REBUILD_BIN` overrides the pinned `darwin-rebuild` path used by `apply`.
- `DOTFILES_SYNC_VSCODE_BIN` overrides the `sync vscode` engine path.
- `XDG_CONFIG_HOME` and `XDG_STATE_HOME` affect the default Neovim runtime paths used by `sync neovim`; override them directly with `--runtime-dir` and `--state-dir` when testing.
- `VSCODE_CODE_BIN` overrides the `code` CLI path; `VSCODE_DATA_HOME`, `VSCODE_EXTENSIONS_DIR`, and `VSCODE_CODE_RETRIES` override VS Code runtime locations and retry behavior.
- `SOPS_AGE_KEY_FILE` overrides the bootstrap / doctor age-key location; otherwise those commands default to `~/.config/sops/age/keys.txt` when `HOME` is available.

Notes:

- `scripts/*.sh` are thin shell wrappers over the Rust CLI.
- `sync neovim` compares `apps/neovim` against `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` and treats `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lazy-lock.json` as the effective Lazy lock when it exists.
- `dotfiles-sync-vscode` is packaged separately; `dotfiles` dispatches `sync vscode` to that binary.
- `ultra` runs VS Code, Neovim, and Emacs setup/sync during activation. `pro` installs editor tooling but leaves setup/sync disabled. Visual Studio Code.app itself is installed manually. Extension IDs to install live under `apps/vscode/` (`_default/extensions.txt` and per-profile `extensions.txt`).

## Checks and development

```bash
nix fmt
nix run .#format
nix flake check \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles
nix develop
```

## Clean export

`export-clean` is tracked-only and requires Git to access a trusted worktree. It fails closed if Git is unavailable or refuses the repository.

```bash
nix run .#dotfiles -- export-clean --format tar --output /tmp/dotfiles-clean.tar
nix run .#export-clean -- --format dir --output /tmp/dotfiles-clean
```

## Manual rebuild

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```
