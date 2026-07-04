[日本語版はこちら](docs/ja/AGENTS.md)

# Repository Guidelines

This repository is a Darwin-first Nix flake for macOS system configuration plus a bounded Linux Home Manager userland target. Keep changes aligned with the current bounded contexts: Darwin hosts/profiles, Linux user environment profiles, typed host truth, explicit mutable surfaces, and a Rust control plane.

## Project Structure

- `flake.nix` — flake inputs/outputs; exposes `darwinConfigurations`, bounded `homeConfigurations` such as `linux_workbench`, and project `templates` (`web-dev`, `rust-dev`, `go-dev`, `python-research`, `data-pipeline`, `native-dev`, `embedded-dev`, `apple-dev`, `infra-nixos`, `infra-iac`, `kubernetes-dev`, `container-oci`, `model-hf`, `docs-dev`, `api-db`, `ai-coding`, `release-dev`).
- `nix/catalog/darwin/` — Darwin host/profile catalog.
- `nix/catalog/linux/` — Linux Home Manager host/profile catalog for userland-only targets.
- `nix/catalog/shared/` — portable profile bundles reused by platform catalogs.
- `nix/lib/module-helpers.nix` — repo-local module helper for `myconfig` feature toggles.
- `nix/modules/` — reusable modules, split into `shared/` and `tools/`.
- `nix/catalog/` — catalog data used by tool modules and ownership checks.
- `nix/local/` — placeholder public facts input for public evaluation.
- `crates/dotfiles-core` — shared Rust support plus shell and Emacs sync implementation.
- `crates/dotfiles-cli` — operational CLI.
- `crates/dotfiles-sync-vscode` — VS Code native profile sync engine.
- `scripts/` — thin shell entrypoints (`apply`, `update`, `doctor`, `bootstrap`, `gc`, `sync`) and smoke tests.
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
- Canonical runtime overrides live in `docs/commands.md` (`HOME`, `DOTFILES_ROOT`, `DOTFILES_PROFILE_DIRS`, `EMACSDIR`, `FACTS*`, `SECRETS*`, `DARWIN_REBUILD_BIN`, `DOTFILES_SYNC_VSCODE_BIN`, `VSCODE_*`, `SOPS_AGE_KEY_FILE`).
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
- `nix build .#homeConfigurations.linux_workbench.activationPackage`
- `home-manager switch --flake .#linux_workbench`
- `nix flake init -t github:atalie2m/dotfiles#web-dev`
- `nix flake init -t github:atalie2m/dotfiles#rust-dev`
- `nix flake init -t github:atalie2m/dotfiles#infra-iac`

## Coding Style

- Nix: 2-space indent, trailing newline, stable attr ordering when reasonable.
- Filenames/dirs: kebab-case; Nix attributes: lowerCamelCase.
- Shell: `#!/usr/bin/env bash` plus `set -euo pipefail`.
- Rust: keep workspace boundaries clear; shared CLI/runtime support belongs in `dotfiles-core`.
- Do not commit host-specific literals; keep them in local facts or secrets inputs.

## Architecture Rules

- Modules must read host truth from `myconfig.hostContext.*`.
- Do not add new direct `config.host.*`, legacy facts option reads, or raw `inputs.local/facts.nix` reads outside the approved host-model/bootstrap boundary.
- Linux Home Manager targets must stay userland-only. Do not move LXC substrate, Tailscale, SSH, storage, observability, or lifecycle ownership out of `domus-ops`.
- Shell sync is implemented by the Rust `dotfiles` CLI (`sync shell`); `scripts/sync.sh` is only a thin shell wrapper.
- Emacs sync is implemented by the Rust `dotfiles` CLI (`sync emacs`) for writable vanilla Emacs config files.
- VS Code sync is implemented by the dedicated `dotfiles-sync-vscode` binary and dispatched through `dotfiles sync vscode`.
- Group toggles are taxonomy; rollout belongs in explicit capability bundles.
- Stock global bundles must not enable project-pinned toolchains. `go`, `nodejs`, `terraform`, and `opentofu` have no host opt-in path and must stay in project templates/devShells; `bun` is the only explicit host opt-in exception.
- Template projects must be documented and guarded as Git flakes. Do not add template instructions that use unfiltered `path:$PWD` refs; keep `target/`, `node_modules/`, `.git/`, and `.direnv/` ignored and source-filtered where local source is copied.

## Git Operating Model

- `main` is the normal protected integration line. `maint/<series>` is allowed
  only for protected maintenance lines; `stabilize/<train>` is allowed only for
  short-lived hardening trains with an expiry.
- Pull Requests are the change objects. Branch names are not authority.
- Human work branches have no naming convention. Everything outside reserved
  namespaces is human work.
- Reserved namespaces are `main`, `maint/**`, `stabilize/**`,
  `svc/<principal-id>/**`, Dependabot refs (`dependabot/**`,
  `dependabot-*`, `dependabot_*`), and `gh-readonly-queue/**`.
- `svc/<principal-id>/**` is only a confinement namespace for an approved
  service principal. The suffix is writer-owned detail and is not a policy
  signal.
- Do not install a general unattended task-agent credential for this
  repository. If a service branch appears without an explicit owner and
  inventory entry, treat it as a credential-scope problem instead of copying
  it.
- Do not encode or parse dates, run IDs, owners, environments, provenance,
  producers, policy lanes, release targets, or issue types in branch names.
- Use short-lived human work branches, open PRs, squash-merge, and delete the
  branch after merge.
- Do not recreate `develop`, `master`, `production`, `staging`, `env/**`,
  `release/**`, `bot/**`, or `chg/**` branches. Treat those names as reserved
  or migration-era examples, not active policy.
- Default-branch migration must preserve existing source SHAs with branch
  rename or fast-forward. Do not squash an existing trunk into a new history.
- The merge authority is the `main` / `maint/**` gate plus required CI and the
  `policy/verdict` check when installed. Service namespaces are defense in
  depth.
- Merge does not mean apply. Repository changes describe desired userland
  configuration; `home-manager switch`, `darwin-rebuild switch`, or `apply`
  remains a deliberate operator action unless the user explicitly asks for it.

## Testing Guidance

- Keep `README.md`, `docs/`, `AGENTS.md`, and `CLAUDE.md` aligned with the actual runtime model.
- Update smoke tests under `scripts/tests/` when changing runtime sync, CLI behavior, or public docs claims.
- Verify Karabiner JSON stays loadable when touching `keyboards/` or `nix/modules/tools/system/karabiner.nix`.

## Security

- Never commit secrets or machine identifiers.
- Keep local machine data in `~/.config/dotfiles/`, not in the repo.
