[日本語版はこちら](docs/ja/CLAUDE.md)

# CLAUDE.md

This file provides repository guidance for coding agents working in this repo.

## Core facts

- Canonical command examples and current host names live in `docs/commands.md`.
- Canonical runtime overrides also live in `docs/commands.md` (`HOME`, `DOTFILES_ROOT`, `DOTFILES_PROFILE_DIRS`, `EMACSDIR`, `FACTS*`, `SECRETS*`, `DARWIN_REBUILD_BIN`, `DOTFILES_SYNC_VSCODE_BIN`, `VSCODE_*`, `SOPS_AGE_KEY_FILE`).
- The supported operational root API is Darwin-first: `darwinConfigurations` plus project `templates`.
- Placeholder public facts live in `nix/local/`; the default secrets input is intentionally inert, and real machines should override both inputs with `~/.config/dotfiles/`.

## Configuration flow

1. `flake.nix` keeps the supported operational root API Darwin-first (`darwinConfigurations` plus project `templates`).
2. The Darwin catalog builds canonical host truth into `config.myconfig.hostContext` from `inputs.local/facts.nix` plus the host declaration.
3. Modules consume `config.myconfig.hostContext.*`, not raw facts.
4. `sops-nix` materializes secrets defined in `inputs.secrets/secrets.nix` at activation time.

## Architecture overview

- `nix/catalog/darwin/`: host/profile catalog and stock profile bundles.
- `nix/modules/`: reusable shared and tool modules.
- `nix/catalog/`: ownership and backend metadata.
- `crates/dotfiles-core`: shared Rust support plus shell and Emacs sync engines.
- `crates/dotfiles-cli`: main operational CLI.
- `crates/dotfiles-sync-vscode`: dedicated VS Code engine.
- `scripts/`: thin shell entrypoints and smoke tests.

## Working rules

- Prefer changing Rust control-plane behavior in the workspace, not in shell wrappers.
- Keep shell limited to thin entrypoints or OS-leaf behavior.
- Keep host truth centralized under `myconfig.hostContext.*`.
- Keep docs accurate when public behavior changes.
- Keep project-pinned toolchains (`nodejs`, `go`, `terraform`, `opentofu`) out of stock global bundles; use project templates/devShells for those versions.
- Keep templates Git-flake-first: no unfiltered `path:$PWD` instructions, and keep `target/`, `node_modules/`, `.git/`, and `.direnv/` out of flake source through ignores and source filters.

## Verification

When toolchains are available, prefer:

- `cargo test`
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
