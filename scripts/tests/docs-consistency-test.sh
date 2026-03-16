#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

require_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq -- "$expected" "$file"; then
    echo "FAIL: expected text missing from $file: $expected" >&2
    exit 1
  fi
}

require_not_contains() {
  local file="$1"
  local forbidden="$2"

  if grep -Fq -- "$forbidden" "$file"; then
    echo "FAIL: forbidden text still present in $file: $forbidden" >&2
    exit 1
  fi
}

require_contains README.md '`pro`: composition of `base + darwin + dev` without VS Code.'
require_contains README.md '`partial`: composition of `base + darwin + dev` with targeted overrides (only `codex` enabled among AI coding agents, VS Code installed but activation sync off).'
require_contains README.md 'Runtime sync operations are implemented through `nix run .#dotfiles -- sync shell`; `scripts/sync.sh` is only a thin shell wrapper over the Rust `dotfiles` CLI.'
require_contains README.md 'The repo ships placeholder public inputs under `nix/local/` and `nix/secrets/` so `darwinConfigurations` always evaluates.'
require_contains docs/commands.md '- Hosts: `pro_mac` (default rice: `pro`), `ultra_mac` (default rice: `ultra`), `minimal_mac` (default rice: `base`)'
require_contains docs/commands.md '- Packages: `dotfiles`, `dotfiles-cli`, `dotfiles-sync-vscode`'
require_contains docs/reconciled-surfaces.md '`nix run .#dotfiles -- sync shell` is the public writable entrypoint manager.'
require_contains docs/reconciled-surfaces.md 'The Rust engine is packaged separately as `dotfiles-sync-vscode`, and `nix run .#dotfiles -- sync vscode` dispatches to it.'
require_contains docs/architecture-reset.md '- the supported operational root surface is Darwin-first'
require_contains docs/architecture-reset.md '- unsupported Home Manager/NixOS trees and Linux contributor outputs were removed'
require_contains AGENTS.md '- `flake.nix` — flake inputs/outputs; exposes `darwinConfigurations` and `templates/web-dev`.'
require_contains AGENTS.md '- Shell sync is implemented by the Rust `dotfiles` CLI (`sync shell`); `scripts/sync.sh` is only a thin shell wrapper.'
require_contains CLAUDE.md '1. `flake.nix` keeps the supported operational root API Darwin-first (`darwinConfigurations` plus `templates.web-dev`).'
require_contains CLAUDE.md '2. Denix hosts build canonical host truth into `config.myconfig.hostContext` from `inputs.local/facts.nix` plus the host declaration.'

for file in README.md docs/commands.md docs/reconciled-surfaces.md docs/architecture-reset.md docs/architecture.md AGENTS.md CLAUDE.md; do
  require_not_contains "$file" 'homeConfigurations'
  require_not_contains "$file" 'nixosConfigurations'
  require_not_contains "$file" 'scripts/sync-adapters/'
  require_not_contains "$file" 'STUB'
done

for file in README.md docs/commands.md docs/reconciled-surfaces.md docs/architecture-reset.md docs/architecture.md AGENTS.md CLAUDE.md; do
  require_not_contains "$file" 'zshrc-compat'
  require_not_contains "$file" 'rootZshrcCompat'
  require_not_contains "$file" '`minimum`'
done

require_not_contains docs/commands.md 'home-manager/release-25.11'
require_not_contains docs/architecture-reset.md 'reduced to an empty compatibility attrset'
require_not_contains docs/architecture-reset.md 'did not delete in-repo NixOS/Home Manager composition trees'
require_not_contains AGENTS.md 'config.facts'
require_not_contains CLAUDE.md 'config.facts'

echo "PASS: docs consistency"
