# Runtime Sync Surfaces

This repository has two runtime sync surfaces and one activation-managed system-app boundary:

- shell entrypoints (runtime sync)
- VS Code native profiles (runtime sync)
- Homebrew/macOS app ownership (activation-managed)

## Shell entrypoints

`scripts/sync-adapters/shell.sh` is the writable entrypoint manager entrypoint, with helper logic split under `scripts/sync-adapters/shell/`.
It compares desired managed content against the current file and repairs the file in place.
Shared shell helpers still come from Home Manager at `~/.config/shell/common.sh`; that file is not part of the runtime sync surface.

- Desired:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
- Actual:
  - `~/.nix/.zshrc`
  - `~/.bashrc`
- State: none
- Model: compare desired managed content against the current target and make the target writable when needed

Behavior:

- Block targets update only the managed marker block and preserve unmanaged content outside the markers.
- `sync shell --apply` will create or restore writable regular files for missing files, writable regular files, `/nix/store/...` symlinks, and readable non-store symlinks.
- `sync shell --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid`.
- Shell sync does not adopt local changes back into the repo.
- Managed macOS login-shell switching supports zsh/bash.

Workflow:

```bash
# 1) Check whether any target needs apply
nix run .#dotfiles -- sync shell --check

# 2) Inspect details and managed-content diffs
nix run .#dotfiles -- sync shell --check --details --diff

# 3) Repair writable entrypoints in place
nix run .#dotfiles -- sync shell --apply
```

## VS Code native profiles

`scripts/sync-adapters/vscode.sh` is a thin dispatcher that executes the Rust engine (`dotfiles-sync-vscode`).
The Rust engine reconciles declarative profile input from `apps/vscode/` into writable VS Code profile state.
The design is intentionally mutable: only the repo-owned subset converges.

- Desired:
  - `apps/vscode/_default/settings.json`
  - `apps/vscode/_default/extensions.txt`
  - `apps/vscode/<profile>/settings.json`
  - `apps/vscode/<profile>/extensions.txt`
- Actual:
  - VS Code native profile settings and extension membership
  - `native` maps to a managed custom profile (`Native`)
  - other profile directories map to custom native profiles
- State:
  - `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode`
  - one JSON state file per managed profile
  - state schema is versioned; older state schemas are treated as `needs-apply` and regenerated on apply
- Model:
  - recursively merge `_default` with the selected profile
  - own the effective settings' top-level keys and effective extension IDs
  - preserve user-added settings keys and extensions outside that owned subset

Behavior:

- `sync vscode --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid`.
- `sync vscode --apply` creates missing native profiles, updates the VS Code profile registry, and reconciles owned settings keys and extensions.
- Previously owned keys/extensions that were removed from `apps/vscode/` are removed on apply.
- User-added keys/extensions that are not owned by the repo are not removed.
- Home Manager activation runs `sync vscode --apply` when VS Code and VS Code sync are both enabled (`tools.editor.vscode.enable` and `tools.editor.vscode.sync.enable`).

Workflow:

```bash
# 1) Check whether any managed profile needs apply
nix run .#dotfiles -- sync vscode --check

# 2) Inspect details and projected diffs
nix run .#dotfiles -- sync vscode --check --details --diff

# 3) Reconcile the owned subset into native VS Code profiles
nix run .#dotfiles -- sync vscode --apply
```

## zsh root compat

Runtime zsh uses `~/.nix/.zshrc`.
Some installers still append to `~/.zshrc`, so there is an opt-in compat helper for that path:

- Script: `scripts/zshrc-compat.sh`
- Nix option: `tools.shell.zsh.rootZshrcCompat.enable`
- Desired compat state: `~/.zshrc -> .nix/.zshrc`

Behavior:

- `--check` reports whether `~/.zshrc` is the expected symlink.
- `--apply` creates the symlink only when `~/.zshrc` is missing.
- `--apply` refuses to overwrite a regular-file `~/.zshrc`, a different symlink, or a special file.
- `--migrate` is the explicit path for moving an existing regular-file `~/.zshrc` into the unmanaged tail of `~/.nix/.zshrc`.

Workflow:

```bash
bash scripts/zshrc-compat.sh --check
bash scripts/zshrc-compat.sh --apply
bash scripts/zshrc-compat.sh --migrate
```

## Homebrew and macOS app ownership boundary

Homebrew and macOS app declarations are reconciled during activation/build (not via `sync`).
The model is declarative ownership with writable runtime data left to upstream tools.

- Desired:
  - `myconfig.tools.*` toggles and catalog ownership data
  - internal Homebrew backend metadata in `nix/catalog/tools/homebrew-ownership.nix`
- Actual:
  - Homebrew-installed formulas/casks and app bundles on macOS
- State:
  - Homebrew's own runtime metadata and Cellar state
  - no repo-managed `lastApplied` state for this boundary
- Model:
  - repo declares ownership and source policy
  - activation ensures declared installs; runtime app/user data remains mutable

Behavior:

- `flake check` enforces ownership validity (duplicate claims, cross-source overlap, unregistered Homebrew items).
- Homebrew package manager internals and app runtime data are unmanaged mutable state.
- Source policy remains: prefer Nix for CLI, Homebrew for macOS-specific/latest-first software.

## Local extension points

Shell-local customization should go in the per-shell local hook files, not in repo-managed blocks:

- zsh: `~/.config/shell/zsh.local.sh`
- bash: `~/.config/shell/bash.local.sh`

## Removed surfaces

- Terminal.app profile sync has been removed from this repository.
- VS Code multi-instance / directory-profile sync has been removed in favor of native profiles plus `sync vscode`.
