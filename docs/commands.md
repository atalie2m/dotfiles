[日本語版はこちら](ja/commands.md)

# Commands

Canonical command examples and current host names live here. Keep README and AI helper files aligned to this page instead of duplicating command surfaces elsewhere.

## Current hosts and packages

- Hosts: `pro_mac` (default rice: `pro`), `ultra_mac` (default rice: `ultra`), `minimal_mac` (default rice: `base`)
- Rices: `base`, `darwin`, `dev`, `pro`, `ultra`, `partial`
- Example darwin targets: `pro_mac`, `ultra_mac`, `minimal_mac`, `ultra_mac-base`, `minimal_mac-ultra`, `pro_mac-partial`
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

```bash
# Apply default rice for each host
nix run .#apply -- --host pro_mac
nix run .#apply -- --host ultra_mac
nix run .#apply -- --host minimal_mac

# Build only
nix run .#apply -- --host ultra_mac --action build

# Switch rices explicitly
nix run .#apply -- --host pro_mac --rice ultra
nix run .#apply -- --host ultra_mac --rice base
nix run .#apply -- --host minimal_mac --rice ultra
nix run .#apply -- --host ultra_mac --rice partial

# Inspect effective group/tool toggles
nix run .#list-tools -- --host pro_mac
nix run .#list-tools -- --host ultra_mac --rice base --format json

# Inspect cross-target toggle matrix
nix run .#matrix-tools
nix run .#matrix-tools -- --format json
nix run .#matrix-tools -- --full --format json

# Bootstrap local inputs
nix run .#bootstrap
nix run .#bootstrap -- --host pro_mac --apply
nix run .#bootstrap -- --host pro_mac --yes

# Health checks
nix run .#doctor
nix run .#doctor -- --host pro_mac
nix run .#doctor -- --host pro_mac --strict
nix run .#doctor -- --json

# Update flake inputs and run checks/builds
UPDATE_SKIP_BUILD=1 nix run .#update
nix run .#update -- --host pro_mac
UPDATE_ALL=1 nix run .#update -- --host pro_mac
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host pro_mac
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

`tools.editor.emacs.enable = true` installs the GUI Emacs app through Homebrew, installs the Doom/Meow sync tooling, and keeps `doom-meow` available under `~/.config/doom/modules/editor/meow`. Doom config files are writable runtime state reconciled by `sync emacs`; Doom itself stays as a mutable checkout at `~/.config/emacs`.

```bash
dotfiles-doom bootstrap
dotfiles-doom sync
dotfiles-doom doctor
```

## Runtime overrides

- `HOME` is required for `nix run .#dotfiles -- sync shell ...`, `nix run .#dotfiles -- sync emacs ...`, `nix run .#dotfiles -- sync neovim ...`, and `nix run .#dotfiles -- sync vscode ...`, and it is also required whenever a command needs repo-default user-scoped paths.
- `DOTFILES_ROOT` overrides flake-root discovery for the Rust CLI and shell wrappers.
- `DOOMDIR` overrides the runtime Doom config directory for `sync emacs`; otherwise it defaults to `~/.config/doom`.
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
- Stock bundles do not run `sync emacs --apply` or `sync vscode --apply` during activation. Enable `tools.editor.emacs.sync.enable = true` or `tools.editor.vscode.sync.enable = true` yourself if you want that automation. Visual Studio Code.app itself is installed manually, and activation skips cleanly when `code` or the app bundle is absent. Extension IDs to install live under `apps/vscode/` (`_default/extensions.txt` and per-profile `extensions.txt`).

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
