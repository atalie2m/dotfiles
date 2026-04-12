[日本語版はこちら](docs/ja/AGENTS.md)

# Repository Guidelines

This repository is a Darwin-first Nix flake for macOS system configuration. Keep changes aligned with the current bounded contexts: Darwin hosts/rices, typed host truth, explicit mutable surfaces, and a Rust control plane.

## Project Structure

- `flake.nix` — flake inputs/outputs; exposes `darwinConfigurations` and `templates` (`web-dev`, `rust-dev`).
- `nix/denix/darwin/{hosts,rices}/` — Darwin host/rice profiles.
- `nix/denix/lib/` — Darwin host constructors and Denix helpers.
- `nix/modules/` — reusable modules, split into `shared/` and `tools/`.
- `nix/catalog/` — catalog data used by tool modules and ownership checks.
- `nix/local/` — placeholder public facts input for public evaluation.
- `crates/dotfiles-core` — shared Rust support and shell sync implementation.
- `crates/dotfiles-cli` — operational CLI.
- `crates/dotfiles-sync-vscode` — VS Code native profile sync engine.
- `scripts/` — thin shell entrypoints (`apply`, `update`, `doctor`, `bootstrap`, `sync`) and smoke tests.
- `nix/scripts/` — Nix expressions consumed by the CLI (`list-tools.nix`, `matrix-tools.nix`, `doctor/facts-schema.nix`).
- `apps/` — app configs (for example `apps/shell/common.sh`, `apps/vscode/...`).
- `surfaces/` — desired state for writable shell entrypoints.
- `keyboards/` — Karabiner complex modifications JSON.

Local inputs live outside Git at `~/.config/dotfiles/`:

- `facts.nix`
- `secrets.nix`
- `files/`

## Build, Test, and Development Commands

- Canonical command examples and current host names live in `docs/commands.md`.
- Canonical runtime overrides live in `docs/commands.md` (`HOME`, `DOTFILES_ROOT`, `FACTS*`, `SECRETS*`, `DARWIN_REBUILD_BIN`, `DOTFILES_SYNC_VSCODE_BIN`, `VSCODE_*`, `SOPS_AGE_KEY_FILE`).
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
- `nix flake init -t github:atalie2m/dotfiles#web-dev`
- `nix flake init -t github:atalie2m/dotfiles#rust-dev`

## Coding Style

- Nix: 2-space indent, trailing newline, stable attr ordering when reasonable.
- Filenames/dirs: kebab-case; Nix attributes: lowerCamelCase.
- Shell: `#!/usr/bin/env bash` plus `set -euo pipefail`.
- Rust: keep workspace boundaries clear; shared CLI/runtime support belongs in `dotfiles-core`.
- Do not commit host-specific literals; keep them in local facts or secrets inputs.

## Architecture Rules

- Modules must read host truth from `myconfig.hostContext.*`.
- Do not add new direct `config.host.*`, legacy facts option reads, or raw `inputs.local/facts.nix` reads outside the approved host-model/bootstrap boundary.
- Shell sync is implemented by the Rust `dotfiles` CLI (`sync shell`); `scripts/sync.sh` is only a thin shell wrapper.
- VS Code sync is implemented by the dedicated `dotfiles-sync-vscode` binary and dispatched through `dotfiles sync vscode`.
- Group toggles are taxonomy; rollout belongs in explicit capability bundles.

## Testing Guidance

- Keep `README.md`, `docs/`, `AGENTS.md`, and `CLAUDE.md` aligned with the actual runtime model.
- Update smoke tests under `scripts/tests/` when changing runtime sync, CLI behavior, or public docs claims.
- Verify Karabiner JSON stays loadable when touching `keyboards/` or `nix/modules/tools/system/karabiner.nix`.

## Security

- Never commit secrets or machine identifiers.
- Keep local machine data in `~/.config/dotfiles/`, not in the repo.
