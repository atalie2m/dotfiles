# Reconciled Surfaces

This repository has two different runtime sync models.
They intentionally do not share the same abstraction anymore.

## Terminal.app

Terminal.app remains a reconciled mutable surface.
It uses the shared reconciler core in `nix/scripts/sync-core.sh` through `nix/scripts/sync-adapters/terminal.sh`.

- Desired: `surfaces/terminal/desired/*.terminal`
- Actual: `~/Library/Preferences/com.apple.Terminal.plist`
- State: `~/.local/state/dotfiles/sync/terminal-app/profiles/*.sha256`
- Model: compare desired, actual, and lastApplied

Terminal workflow:

```bash
# 1) Detect drift
nix run .#dotfiles -- sync terminal --check

# 2) Inspect details and diff
nix run .#dotfiles -- sync terminal --check --details --diff

# 3) Adopt current local changes when they are intentional
nix run .#dotfiles -- sync terminal --adopt
nix run .#dotfiles -- sync terminal --adopt --in-place
nix run .#dotfiles -- sync terminal --adopt --in-place --force

# 4) Apply repo state back into Terminal.app
nix run .#dotfiles -- sync terminal --apply
nix run .#dotfiles -- sync terminal --apply --force

# 5) Forget lastApplied state when needed
nix run .#dotfiles -- sync terminal --forget
```

## Shell

Shell is not treated as a generic reconciled surface.
`nix/scripts/sync-adapters/shell.sh` is a standalone writable entrypoint manager.
It does not use `sync-core.sh` and it does not keep shell-specific `lastApplied` state.

- Desired: `surfaces/shell/desired/*`
- Actual:
  - `~/.nix/.zshrc`
  - `~/.bashrc`
  - `~/.config/fish/config.fish`
  - `~/.config/fish/conf.d/00-dotfiles.fish`
- State: none
- Model: compare desired managed content against the current entrypoint/file and repair in place

Shell behavior:

- Block targets update only the managed marker block and preserve unmanaged content outside the markers.
- `sync shell --apply` will create or restore writable regular files for common entrypoint shapes, including missing files and symlinks.
- `sync shell --check` reports `in-sync`, `needs-apply`, `missing`, or `invalid` based on the current target state.
- Shell sync does not adopt local changes back into the repo.

Shell workflow:

```bash
# 1) Check whether any target needs apply
nix run .#dotfiles -- sync shell --check

# 2) Inspect details and managed-content diffs
nix run .#dotfiles -- sync shell --check --details --diff

# 3) Repair writable entrypoints in place
nix run .#dotfiles -- sync shell --apply
```

## Adapter Contract

Only Terminal currently uses the shared `sync-core.sh` adapter contract.
That contract still requires functions such as:

- `sync_adapter_list_items`
- `sync_adapter_is_selected`
- `sync_adapter_state_key`
- `sync_adapter_extract_desired`
- `sync_adapter_extract_actual`
- `sync_adapter_write_desired_to_actual`
- `sync_adapter_export_actual`
- `sync_adapter_on_no_selection`

Shell does not implement these hooks anymore.
