# Repository Guidelines

This repository is a Nix flake–based macOS dotfiles setup using nix-darwin, Home Manager, Denix, and brew-nix. Follow these conventions to keep changes consistent and reproducible.

## Project Structure & Module Organization
- `flake.nix` — flake inputs/outputs; exposes `darwinConfigurations` and `homeConfigurations` and a `templates/web-dev` flake template.
- `nix/denix/hosts/{common,commercial}/` — host profiles and system-level options.
- `nix/denix/modules/` — reusable modules (programs, packages, shells, services, etc.).
- `nix/denix/rices/` — higher‑level bundles (e.g., `full`, `minimum`).
- `nix/env.nix` — machine/user facts populated via Git filters; do not hardcode values elsewhere.
- `apps/` — user app configs (e.g., `apps/starship.toml`, `apps/vscode/...`).
- `keyboards/` — Karabiner complex modifications JSON.
- `.git-filters/` — clean/smudge filters for system info; run via `./setup-env.sh`.

## Build, Test, and Development Commands
- `./setup-env.sh` — configures Git filters and repopulates `nix/env.nix` (requires clean tree).
- `nix flake check` — validates flake, runs basic checks.
- `darwin-rebuild build --flake .#common` — builds the `common` host; swap to `#commercial` as needed.
- `sudo darwin-rebuild switch --flake .#common` — applies the built configuration.
- Template: `nix flake init -t github:atalie2m/dotfiles#web-dev` (see `templates/web-dev`).

## Coding Style & Naming Conventions
- Nix: 2‑space indent, trailing newline, stable attr ordering when reasonable. Prefer small modules under `nix/denix/modules/` with clear options.
- Filenames/dirs: kebab‑case; Nix attributes: lowerCamelCase; constants via `nix/env.nix`.
- Shell: `#!/usr/bin/env bash` with `set -euo pipefail` (see existing scripts).
- Do not commit host‑specific literals; use placeholders and filters.

## Testing Guidelines
- Primary: `nix flake check` and `darwin-rebuild build --flake .#(host)` for all touched hosts.
- Verify Karabiner JSON loads by linking or via Home Manager if applicable.
- Keep changes minimal; include rollback notes when altering critical modules.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat(scope): ...`, `fix(module): ...`, `chore(ci): ...`, `refactor(...): ...` (see `git log`).
- PRs must include: summary, affected paths/modules, test commands/output (`nix flake check`, build logs), and migration notes if user‑visible behavior changes.
- Link related issues; add small screenshots only when UI config changes (e.g., Starship/terminal visuals).

## Security & Configuration Tips
- Run `./setup-env.sh` after cloning; it requires a clean working tree.
- Never commit secrets or machine identifiers; filters convert them to placeholders.
