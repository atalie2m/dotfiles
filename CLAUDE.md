# CLAUDE.md

This file provides repository guidance for coding agents working in this repo.

## Core facts

- Canonical command examples and current host names live in `docs/commands.md`.
- The supported operational root API is Darwin-first: `darwinConfigurations` plus `templates.web-dev`.
- Placeholder public inputs live in `nix/local/` and `nix/secrets/`, but real machines should override both with `~/.config/dotfiles/`.

## Configuration flow

1. `flake.nix` keeps the supported operational root API Darwin-first (`darwinConfigurations` plus `templates.web-dev`).
2. Denix hosts build canonical host truth into `config.myconfig.hostContext` from `inputs.local/facts.nix` plus the host declaration.
3. Modules consume `config.myconfig.hostContext.*`, not raw facts.
4. `sops-nix` materializes secrets defined in `inputs.secrets/secrets.nix` at activation time.

## Architecture overview

- `nix/denix/darwin/`: host and rice composition only.
- `nix/modules/`: reusable shared and tool modules.
- `nix/catalog/`: ownership and backend metadata.
- `crates/dotfiles-core`: shared Rust support and shell sync engine.
- `crates/dotfiles-cli`: main operational CLI.
- `crates/dotfiles-sync-vscode`: dedicated VS Code engine.
- `scripts/`: thin shell entrypoints and smoke tests.

## Working rules

- Prefer changing Rust control-plane behavior in the workspace, not in shell wrappers.
- Keep shell limited to thin entrypoints or OS-leaf behavior.
- Keep host truth centralized under `myconfig.hostContext.*`.
- Keep docs accurate when public behavior changes.
- Follow the Git branch strategy in `docs/git-branch-strategy.md`: `main` is
  the only long-lived branch, `supervised/**` is for human or supervised-agent
  work, and `deps/**` is for dependency automation.
- Do not create or copy `unattended/**` branches in this repository. The
  unattended task-agent credential should not be installed for dotfiles.
- Read only the first branch segment as policy. Do not encode or parse dates,
  run IDs, owners, environments, provenance, release targets, or issue types in
  the branch suffix.
- Merge does not mean apply. Do not run `home-manager switch`,
  `darwin-rebuild switch`, or `nix run .#apply` unless the active task
  explicitly authorizes local activation.

## Verification

When toolchains are available, prefer:

- `cargo test`
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
