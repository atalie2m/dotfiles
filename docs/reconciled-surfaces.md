# Reconciled Surfaces

This repository uses a shared reconciler core (`nix/scripts/sync-core.sh`) for user-writable runtime state.
Each surface compares three values per item: desired (repo), actual (local machine), and lastApplied (state hash).

## Active Surfaces

- Shell managed blocks (`nix/scripts/sync.sh shell`, adapter: `nix/scripts/sync-adapters/shell.sh`)
  - Desired: `surfaces/shell/desired/*`
  - Actual: `~/.nix/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish`, `~/.config/fish/conf.d/00-dotfiles.fish`
  - State: `~/.local/state/dotfiles/sync/shell/blocks/*.sha256`
- Terminal.app profiles (`nix/scripts/sync.sh terminal`, adapter: `nix/scripts/sync-adapters/terminal.sh`)
  - Desired: `surfaces/terminal/desired/*.terminal`
  - Actual: `~/Library/Preferences/com.apple.Terminal.plist`
  - State: `~/.local/state/dotfiles/sync/terminal-app/profiles/*.sha256`

## Drift Workflow

Use the same workflow for both adapters.

```bash
# 1) Detect drift
nix run .#dotfiles -- sync shell --check
nix run .#dotfiles -- sync terminal --check

# 2) Inspect details and diff
nix run .#dotfiles -- sync shell --check --details --diff
nix run .#dotfiles -- sync terminal --check --details --diff

# 3a) Adopt current local changes into staged files (safe default)
nix run .#dotfiles -- sync shell --adopt
nix run .#dotfiles -- sync terminal --adopt

# 3b) Adopt directly into repo files (conflicts require --force)
nix run .#dotfiles -- sync shell --adopt --in-place
nix run .#dotfiles -- sync terminal --adopt --in-place
nix run .#dotfiles -- sync shell --adopt --in-place --force
nix run .#dotfiles -- sync terminal --adopt --in-place --force

# 4) For shell entrypoints, run one-time migration when shape/type is invalid
nix run .#dotfiles -- sync shell --migrate

# 5) Apply repo to local state
nix run .#dotfiles -- sync shell --apply
nix run .#dotfiles -- sync terminal --apply

# 6) Force apply only when intentionally overwriting local drift
nix run .#dotfiles -- sync shell --apply --force
nix run .#dotfiles -- sync terminal --apply --force
```

Legacy state directories are no longer read by adapters and are intentionally ignored.

## Adapter Contract

Every adapter that uses `sync-core.sh` must define:

- `sync_adapter_list_items`
- `sync_adapter_is_selected`
- `sync_adapter_state_key`
- `sync_adapter_extract_desired`
- `sync_adapter_extract_actual`
- `sync_adapter_write_desired_to_actual`
- `sync_adapter_export_actual`
- `sync_adapter_on_no_selection`
- `sync_adapter_print_summary`

Optional hooks (`sync_adapter_after_apply`, `sync_adapter_print_details`, `sync_adapter_print_diff`, etc.) are for adapter-specific behavior only and should stay minimal.
