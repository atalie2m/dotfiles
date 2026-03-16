# Runtime Sync Surfaces

This repository has two runtime sync surfaces and one activation-managed system-app boundary:

- shell entrypoints
- VS Code native profiles
- Homebrew/macOS app ownership

## Shell entrypoints

`nix run .#dotfiles -- sync shell` is the public writable entrypoint manager.
The control plane is implemented in Rust. `scripts/sync.sh` is only a thin shell wrapper.
Shared shell helpers still come from Home Manager at `~/.config/shell/common.sh`; that file is not part of runtime sync state.

- Desired:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
- Actual:
  - `~/.nix/.zshrc`
  - `~/.bashrc`
- State: none
- Model: compare repo-managed block content against the current target and materialize writable regular files when needed

Behavior:

- block targets update only the managed marker block and preserve unmanaged content outside the markers
- `sync shell --apply` repairs missing files, writable regular files, `/nix/store/...` symlinks, and readable non-store symlinks
- `sync shell --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid`
- shell sync does not adopt local changes back into the repo

## VS Code native profiles

The Rust engine is packaged separately as `dotfiles-sync-vscode`, and `nix run .#dotfiles -- sync vscode` dispatches to it.
The design is intentionally mutable: only the repo-owned subset converges.

- Desired:
  - `apps/vscode/_default/settings.json`
  - `apps/vscode/_default/extensions.txt`
  - `apps/vscode/<profile>/settings.json`
  - `apps/vscode/<profile>/extensions.txt`
- Actual:
  - VS Code native profile settings and extension membership
- State:
  - `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode`
  - one JSON state file per managed profile
- Model:
  - recursively merge `_default` with the selected profile
  - own the effective settings top-level keys and effective extension IDs
  - preserve user-added settings keys and extensions outside that owned subset

Behavior:

- `sync vscode --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid`
- `sync vscode --apply` creates missing profiles, updates the profile registry, and reconciles owned settings keys and extensions
- previously owned keys/extensions removed from `apps/vscode/` are removed on apply
- user-added keys/extensions not owned by the repo are preserved
- activation runs `sync vscode --apply` when both `tools.editor.vscode.enable` and `tools.editor.vscode.sync.enable` are true

## Homebrew and macOS app ownership

Homebrew and macOS app declarations are reconciled during activation/build, not via `sync`.
The model is declarative ownership with writable runtime data left to upstream tools.

- Desired:
  - `myconfig.tools.*` toggles and catalog ownership data
  - internal Homebrew backend metadata in `nix/catalog/tools/homebrew-ownership.nix`
- Actual:
  - Homebrew-installed formulas/casks and app bundles
- State:
  - Homebrew's own runtime metadata
- Model:
  - repo declares ownership and source policy
  - activation ensures declared installs; runtime app/user data remains mutable

## Removed surfaces

- Terminal.app profile sync has been removed
- Linux contributor outputs have been removed from the root flake
