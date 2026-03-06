# Runtime Sync Surfaces

This repository now has one runtime sync surface: shell entrypoints.
The design is intentionally small and stateless.

## Shell entrypoints

`nix/scripts/sync-adapters/shell.sh` is a standalone writable entrypoint manager.
It compares desired managed content against the current file and repairs the file in place.

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

## zsh root compat

Runtime zsh uses `~/.nix/.zshrc`.
Some installers still append to `~/.zshrc`, so there is an opt-in compat helper for that path:

- Script: `nix/scripts/zshrc-compat.sh`
- Nix option: `tools.shell.zsh.rootZshrcCompat.enable`
- Desired compat state: `~/.zshrc -> .nix/.zshrc`

Behavior:

- `--check` reports whether `~/.zshrc` is the expected symlink.
- `--apply` creates the symlink only when `~/.zshrc` is missing.
- `--apply` refuses to overwrite a regular-file `~/.zshrc`, a different symlink, or a special file.
- `--migrate` is the explicit path for moving an existing regular-file `~/.zshrc` into the unmanaged tail of `~/.nix/.zshrc`.

Workflow:

```bash
bash nix/scripts/zshrc-compat.sh --check
bash nix/scripts/zshrc-compat.sh --apply
bash nix/scripts/zshrc-compat.sh --migrate
```

## Local extension points

Shell-local customization should go in the per-shell local hook files, not in repo-managed blocks:

- zsh: `~/.config/shell/zsh.local.sh`
- bash: `~/.config/shell/bash.local.sh`

## Removed surface

Terminal.app profile sync has been removed from this repository.
Use a true-color terminal instead, or manage Terminal.app manually if you still need it.
