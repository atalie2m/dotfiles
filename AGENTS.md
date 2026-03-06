# Repository Guidelines

This repository is a Nix flake–based macOS dotfiles setup using nix-darwin, Home Manager, Denix, and brew-nix. Follow these conventions to keep changes consistent and reproducible.

## Project Structure & Module Organization
- `flake.nix` — flake inputs/outputs; exposes `darwinConfigurations` and `homeConfigurations` and a `templates/web-dev` flake template.
- `nix/denix/darwin/{hosts,rices}/` — Darwin host/rice profiles.
- `nix/denix/nixos/{hosts,rices}/` — NixOS host/rice profiles.
- `nix/denix/home/{hosts,rices}/` — dedicated Home Manager host/rice profiles.
- `nix/denix/modules/` — reusable modules (programs, packages, shells, services, etc.).
- `nix/local/` — stub local facts input (`facts.nix`, `STUB`) for public evaluation.
- `nix/secrets/` — stub local secrets input (`secrets.nix`, `STUB`) for public evaluation.
- `nix/scripts/` — CLI entrypoints (`apply`, `update`, `doctor`, `bootstrap`) and shared helpers.
- `apps/` — user app configs (e.g., `apps/starship.toml`, `apps/vscode/...`).
- `surfaces/` — desired state for writable shell entrypoints (`surfaces/shell/desired`).
- `keyboards/` — Karabiner complex modifications JSON.
- Local facts live at `~/.config/dotfiles/facts.nix` (not in Git).
- Local secrets live at `~/.config/dotfiles/secrets.nix` and `~/.config/dotfiles/files/` (not in Git).
- Both inputs default to the same base directory: `~/.config/dotfiles/`.

## Build, Test, and Development Commands
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles` — validates flake, runs basic checks.
- `nix run .#apply -- --host a2m_mac --action build` — builds the `a2m_mac` host (default rice: full); add `--rice <rice>` or swap host as needed.
- `nix run .#apply -- --host a2m_mac` — applies the built configuration (uses `sudo -E` internally).
- Template: `nix flake init -t github:atalie2m/dotfiles#web-dev` (see `templates/web-dev`).

## Coding Style & Naming Conventions
- Nix: 2‑space indent, trailing newline, stable attr ordering when reasonable. Prefer small modules under `nix/denix/modules/` with clear options.
- Filenames/dirs: kebab‑case; Nix attributes: lowerCamelCase; constants via `config.facts`.
- Shell: `#!/usr/bin/env bash` with `set -euo pipefail` (see existing scripts).
- Do not commit host‑specific literals; keep them in local facts or secrets inputs.

## Testing Guidelines
- Primary: `nix flake check` and `nix run .#apply -- --host <host> --action build` (or `darwin-rebuild build --flake .#<host>`) for all touched hosts.
- Verify Karabiner JSON loads by linking or via Home Manager if applicable.
- Keep changes minimal; include rollback notes when altering critical modules.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat(scope): ...`, `fix(module): ...`, `chore(ci): ...`, `refactor(...): ...` (see `git log`).
- PRs must include: summary, affected paths/modules, test commands/output (`nix flake check`, build logs), and migration notes if user‑visible behavior changes.
- Link related issues; add small screenshots only when UI config changes (e.g., Starship/terminal visuals).

## Security & Configuration Tips
- Never commit secrets or machine identifiers; keep them in local facts/secrets inputs.

## Runtime Sync
- Shell sync is implemented directly in `nix/scripts/sync-adapters/shell.sh`.
- The public entrypoint is `nix/scripts/sync.sh`, and it only dispatches the `shell` surface.
- Shell sync is stateless: it does not keep `lastApplied` hashes or any shell-specific state directory.
- Add/update smoke tests under `nix/scripts/` and keep `docs/reconciled-surfaces.md` and `README.md` aligned with the runtime model.
