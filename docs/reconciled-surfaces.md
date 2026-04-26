[日本語版はこちら](ja/reconciled-surfaces.md)

# Runtime Sync Surfaces

This repository has four runtime sync surfaces and one activation-managed system-app boundary:

- shell entrypoints
- Doom Emacs config
- Neovim config
- VS Code native profiles
- Home Manager-owned XDG config files
- Homebrew/macOS app ownership

## Shell entrypoints

`nix run .#dotfiles -- sync shell` is the public writable entrypoint manager.
The control plane is implemented in Rust. `scripts/sync.sh` is only a thin shell wrapper.
Shared shell helpers still come from Home Manager at `~/.config/shell/common.sh`, and the repo's `scripts/` directory is added to `PATH` when shell tooling is enabled; neither surface is part of runtime sync state.

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

## Doom Emacs config

`nix run .#dotfiles -- sync emacs` is the public writable Doom config manager.
The control plane is implemented in Rust in `dotfiles-core`; `scripts/sync.sh` is only a thin shell wrapper.

- Desired:
  - `apps/emacs/doom/init.el`
  - `apps/emacs/doom/packages.el`
  - `apps/emacs/doom/config.el`
- Actual:
  - `${DOOMDIR:-~/.config/doom}/init.el`
  - `${DOOMDIR:-~/.config/doom}/packages.el`
  - `${DOOMDIR:-~/.config/doom}/config.el`
- State: none
- Model: compare fully repo-owned Doom config files against writable runtime files
- Contract: Doom config files converge fully to repo state on apply

Behavior:

- `sync emacs --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid`
- `sync emacs --apply` creates or rewrites the writable runtime Doom config files from the repo
- `sync emacs --adopt` copies runtime Doom config edits back into `apps/emacs/doom/`
- `--item init`, `--item packages`, or `--item config` restricts reconciliation to one file
- `tools.editor.emacs.enable` owns the Emacs app, sync tooling, and external `doom-meow` module; Doom itself remains a mutable checkout
- Doom is installed at `${EMACSDIR:-~/.emacs.d}` so standard GUI/daemon startup uses it directly
- `tools.editor.emacs.bootstrap.enable` runs `dotfiles-doom bootstrap` only when `${EMACSDIR:-~/.emacs.d}/bin/doom` is missing
- stock `dev`-derived bundles enable activation-time Emacs sync and first-run Doom bootstrap

## Neovim config

`nix run .#dotfiles -- sync neovim` is the public Neovim config drift manager.
The control plane is implemented in Rust in `dotfiles-core`; the `nvim` sync surface alias is also accepted.

- Desired:
  - `apps/neovim/**`
  - `apps/neovim/lazy-lock.json`
- Actual:
  - `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/**`
  - `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lazy-lock.json` when present, otherwise `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json`
- State:
  - Neovim/LazyVim runtime state under `${XDG_STATE_HOME:-$HOME/.local/state}/nvim`
- Model:
  - compare the repo-owned Neovim config tree against the runtime config tree
  - treat state-local `lazy-lock.json` as the effective Lazy lock because the repo config can be Nix-managed and read-only

Behavior:

- `sync neovim --check` reports `in-sync`, `needs-apply`, `missing`, `runtime-only`, or `invalid`
- `sync neovim --apply` materializes repo files into a writable runtime config dir and writes the effective lock into the state dir when no lock exists yet
- `sync neovim --adopt` imports changed/runtime-only runtime config files and the effective Lazy lock back into `apps/neovim/`
- adopt is non-destructive: if a repo-managed file is missing from runtime, it refuses that item instead of deleting it from the repo
- when the runtime config dir is a symlink, `--apply` refuses non-lock rewrites; use Home Manager activation for the linked tree or pass an explicit writable `--runtime-dir`

## VS Code native profiles

The Rust engine is packaged separately as `dotfiles-sync-vscode`, and `nix run .#dotfiles -- sync vscode` dispatches to it.
The design is intentionally mutable: managed profile settings files converge fully to the repo state, while extension ownership remains selective.

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
  - write the effective settings file as fully repo-owned profile state
  - own the effective extension IDs and preserve user-added extensions outside repo ownership

Behavior:

- `sync vscode --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid`
- `sync vscode --apply` creates missing profiles, updates the profile registry, rewrites managed settings files, and reconciles repo-owned extensions
- settings removed from `apps/vscode/` disappear on the next apply because the managed file is fully repo-owned
- user-added extensions not owned by the repo are preserved
- `tools.editor.vscode.enable` owns the VS Code sync tooling and managed profile surface; Visual Studio Code.app itself is installed manually
- stock bundles do not run `sync vscode --apply` during activation; set `tools.editor.vscode.sync.enable = true` yourself if you want activation-time reconciliation, which still skips cleanly if VS Code is not installed yet

## Home Manager-owned XDG config files

Some CLI/TUI defaults are normal Home Manager files rather than Rust `sync`
surfaces. Examples include `~/.config/television/config.toml`,
`~/.config/zellij/config.kdl`, `~/.config/k9s/*`, and gh configuration
generated by `programs.gh`.

Behavior:

- activation links repo-owned config files into place when the matching
  `myconfig.tools.*` toggle is enabled
- if a pre-existing unmanaged file blocks the first activation, nix-darwin
  moves it aside in the same directory with the `.hm-backup` suffix before
  creating the managed link
- after the managed link exists, later activation converges the file to the
  repo state

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
  - dedicated feature modules such as `tools.system.karabiner` own install policy, while `tools.editor.emacs` and `tools.editor.vscode` own repo-managed editor state plus sync tooling

## Removed surfaces

- Terminal.app profile sync has been removed
- Linux contributor outputs have been removed from the root flake
