[日本語版はこちら](ja/architecture.md)

# Architecture

This repository keeps Darwin composition, reusable modules, catalog data, and runtime tooling in separate trees so each layer can evolve independently.

For the reset rationale and before/after summary, see [`docs/architecture-reset.md`](architecture-reset.md).

## Layout

- `nix/catalog/darwin`: Darwin host/profile catalog and stock profile bundles
- `nix/lib`: host model, module helpers, and shared policy helpers
- `nix/modules/shared`: canonical host model wiring, system modules, and shared Nixpkgs policy
- `nix/modules/tools`: user-facing tool modules grouped by capability
- `nix/catalog/tools`: declarative tool ownership data for Nixpkgs and Homebrew-backed tools
- `crates/dotfiles-core`: shared Rust support plus shell, Emacs, Neovim sync, and agent notification implementations
- `crates/dotfiles-cli`: operational CLI (`apply`, `agent-notify`, `update`, `doctor`, `bootstrap`, `export-clean`, `list-tools`, `matrix-tools`, `sync`)
- `crates/dotfiles-sync-vscode`: dedicated VS Code native profile reconciliation engine
- `scripts/`: thin shell entrypoints and smoke/integration tests
- `nix/scripts/`: Nix expressions used by CLI helpers (`list-tools.nix`, `matrix-tools.nix`, `doctor/facts-schema.nix`)
- `apps/`, `surfaces/`, and `keyboards/`: repo-managed assets consumed by modules and runtime sync

## Wiring rules

- `flake.nix` passes `repoPaths` through `specialArgs`, and modules use that instead of deep relative imports
- user-facing option paths stay under `myconfig.*`
- host truth for modules lives under `myconfig.hostContext.*`
- raw facts imports are limited to the host-model/bootstrap boundary
- shell under `scripts/` is limited to thin entrypoints, not the control plane

## Practical implications

- the supported operational root flake API is Darwin-first
- if you add a reusable feature, put it in `nix/modules/` and keep `nix/catalog/darwin` focused on host/profile composition
- if you add catalog-owned tools, update the relevant registry/catalog data under `nix/catalog/tools/`
- if you add operational CLI behavior, implement it in the Rust workspace first and keep shell thin
