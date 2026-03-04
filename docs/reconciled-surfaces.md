# Reconciled Surfaces

This repository uses a shared reconciler core (`nix/scripts/sync-core.sh`) for user-writable runtime state.
Each surface compares three values per item: desired (repo), actual (local machine), and lastApplied (state hash).

## Active Surfaces

- Shell managed blocks (`nix/scripts/shell.sh`)
  - Desired: `apps/shell/managed/*`
  - Actual: `~/.nix/.zshrc`, `~/.bashrc`, `~/.bashrc.local`, `~/.config/fish/config.fish`, `~/.config/fish/conf.d/00-dotfiles.fish`
  - State: `~/.local/state/dotfiles/sync/shell/blocks/*.sha256`
- Terminal.app profiles (`nix/scripts/terminal.sh`)
  - Desired: `apps/terminal/*.terminal`
  - Actual: `~/Library/Preferences/com.apple.Terminal.plist`
  - State: `~/.local/state/dotfiles/sync/terminal-app/profiles/*.sha256`

## Drift Workflow

Use the same workflow for both adapters.

```bash
# 1) Detect drift
nix run .#dotfiles -- shell sync --check
nix run .#dotfiles -- terminal sync --check

# 2) Inspect details and diff
nix run .#dotfiles -- shell sync --check --details --diff
nix run .#dotfiles -- terminal sync --check --details --diff

# 3a) Adopt current local changes into staged files (safe default)
nix run .#dotfiles -- shell sync --adopt
nix run .#dotfiles -- terminal sync --adopt

# 3b) Adopt directly into repo files (conflicts require --force)
nix run .#dotfiles -- shell sync --adopt --in-place
nix run .#dotfiles -- terminal sync --adopt --in-place
nix run .#dotfiles -- shell sync --adopt --in-place --force
nix run .#dotfiles -- terminal sync --adopt --in-place --force

# 4) Apply repo to local state
nix run .#dotfiles -- shell sync --apply
nix run .#dotfiles -- terminal sync --apply

# 5) Force apply only when intentionally overwriting local drift
nix run .#dotfiles -- shell sync --apply --force
nix run .#dotfiles -- terminal sync --apply --force
```

## State Migration

Legacy state directories are no longer read by adapters. Migrate explicitly:

```bash
nix run .#dotfiles -- migrate-state --dry-run
nix run .#dotfiles -- migrate-state --force
```

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

