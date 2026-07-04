[日本語版はこちら](docs/ja/CLAUDE.md)

# CLAUDE.md

This file provides repository guidance for coding agents working in this repo.

## Core facts

- Canonical command examples and current host names live in `docs/commands.md`.
- Canonical runtime overrides also live in `docs/commands.md` (`HOME`, `DOTFILES_ROOT`, `DOTFILES_PROFILE_DIRS`, `EMACSDIR`, `FACTS*`, `SECRETS*`, `DARWIN_REBUILD_BIN`, `DOTFILES_SYNC_VSCODE_BIN`, `VSCODE_*`, `SOPS_AGE_KEY_FILE`).
- The supported operational root API is Darwin-first: `darwinConfigurations`, bounded `homeConfigurations` such as `linux_workbench`, plus project `templates`.
- Placeholder public facts live in `nix/local/`; the default secrets input is intentionally inert, and real machines should override both inputs with `~/.config/dotfiles/`.

## Configuration flow

1. `flake.nix` keeps the supported operational root API Darwin-first (`darwinConfigurations`, bounded Linux Home Manager `homeConfigurations`, plus project `templates`).
2. The platform catalogs build canonical host truth into `config.myconfig.hostContext` from `inputs.local/facts.nix` plus the host declaration.
3. Modules consume `config.myconfig.hostContext.*`, not raw facts.
4. `sops-nix` materializes secrets defined in `inputs.secrets/secrets.nix` at activation time.

## Architecture overview

- `nix/catalog/darwin/`: Darwin host/profile catalog and stock profile bundles.
- `nix/catalog/linux/`: Linux Home Manager host/profile catalog for userland-only targets.
- `nix/catalog/shared/`: portable profile bundles reused by platform catalogs.
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
- Keep Linux Home Manager targets userland-only; `domus-ops` owns LXC substrate, storage, Tailscale, SSH, observability, and lifecycle.
- Keep docs accurate when public behavior changes.
- Keep project-pinned toolchains out of stock global bundles. `go`, `nodejs`, `terraform`, and `opentofu` must stay in project templates/devShells with no host opt-in path; `bun` is the only explicit host opt-in exception.
- Keep templates Git-flake-first: no unfiltered `path:$PWD` instructions, and keep `target/`, `node_modules/`, `.git/`, and `.direnv/` out of flake source through ignores and source filters.
- Follow the Git branch strategy in `docs/git-branch-strategy.md`: Pull
  Requests are the change objects, branch names are not authority, and human
  work branches have no naming convention.
- Use reserved namespaces only for their intended purpose: `main`,
  `maint/**`, `stabilize/**`, `svc/<principal-id>/**`, Dependabot refs, and
  `gh-readonly-queue/**`.
- Do not install a general unattended task-agent credential for dotfiles. A
  service branch needs an explicit principal owner and inventory entry.
- Do not encode or parse dates, run IDs, owners, environments, provenance,
  producers, policy lanes, release targets, or issue types in branch names.
- Merge does not mean apply. Do not run `home-manager switch`,
  `darwin-rebuild switch`, or `nix run .#apply` unless the active task
  explicitly authorizes local activation.

## Verification

When toolchains are available, prefer:

- `cargo test`
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
- `nix build .#homeConfigurations.linux_workbench.activationPackage`
