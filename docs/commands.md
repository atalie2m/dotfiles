# Commands

Canonical command examples and current host names live here. Keep README and AI helper files aligned to this page instead of duplicating command surfaces elsewhere.

## Current hosts and packages

- Hosts: `pro_mac` (default rice: `pro`), `ultra_mac` (default rice: `ultra`), `minimal_mac` (default rice: `base`)
- Rices: `base`, `darwin`, `dev`, `pro`, `ultra`, `partial`
- Example darwin targets: `pro_mac`, `ultra_mac`, `minimal_mac`, `ultra_mac-base`, `minimal_mac-ultra`, `pro_mac-partial`
- Packages: `dotfiles`, `dotfiles-cli`, `dotfiles-sync-vscode`

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

# VS Code native profiles
nix run .#dotfiles -- sync vscode --check
nix run .#dotfiles -- sync vscode --check --details --diff
nix run .#dotfiles -- sync vscode --apply
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native
```

Notes:

- `scripts/*.sh` are thin shell wrappers over the Rust CLI.
- `dotfiles-sync-vscode` is packaged separately; `dotfiles` dispatches `sync vscode` to that binary.
- `sync vscode --apply` also runs during activation when both `tools.editor.vscode.enable = true` and `tools.editor.vscode.sync.enable = true` (stock capability bundles: **`ultra` rice only**). Extension IDs to install live under `apps/vscode/` (`_default/extensions.txt` and per-profile `extensions.txt`).

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
