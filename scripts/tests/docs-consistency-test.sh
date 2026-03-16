#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

DOC_FILES=(
  README.md
  docs/commands.md
  docs/reconciled-surfaces.md
  docs/architecture-reset.md
  docs/architecture.md
  docs/vscode.md
  AGENTS.md
  CLAUDE.md
)

require_contains_anywhere() {
  local expected="$1"
  local found=0
  local file
  for file in "${DOC_FILES[@]}"; do
    if grep -Fq -- "$expected" "$file"; then
      found=1
      break
    fi
  done
  if [[ $found -ne 1 ]]; then
    echo "FAIL: expected semantic invariant missing from docs: $expected" >&2
    exit 1
  fi
}

require_not_contains_anywhere() {
  local forbidden="$1"
  local file
  for file in "${DOC_FILES[@]}"; do
    if grep -Fq -- "$forbidden" "$file"; then
      echo "FAIL: forbidden text still present in $file: $forbidden" >&2
      exit 1
    fi
  done
}

require_contains_file() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    echo "FAIL: expected text missing from $file: $expected" >&2
    exit 1
  fi
}

require_contains_anywhere 'darwinConfigurations'
require_contains_anywhere 'nix run .#dotfiles -- sync shell'
require_contains_anywhere 'nix run .#dotfiles -- sync vscode'
require_contains_anywhere 'dotfiles-sync-vscode'

require_contains_file README.md 'managed profile settings are fully repo-owned'
require_contains_file docs/reconciled-surfaces.md 'managed profile settings files converge fully to the repo state'
require_contains_file docs/vscode.md 'manual settings changes inside a managed profile are overwritten on the next apply'
require_contains_file docs/vscode.md 'VS Code'\''s built-in `Default` profile is intentionally unmanaged'
require_contains_file docs/commands.md 'These commands are Darwin-only and resolve `darwinConfigurations`.'

for file in "${DOC_FILES[@]}"; do
  require_not_contains_anywhere 'homeConfigurations'
  require_not_contains_anywhere 'nixosConfigurations'
  require_not_contains_anywhere 'scripts/sync-adapters/'
  require_not_contains_anywhere 'STUB'
  require_not_contains_anywhere 'zshrc-compat'
  require_not_contains_anywhere 'rootZshrcCompat'
done

require_not_contains_anywhere '`minimum`'
require_not_contains_anywhere 'owned subset of settings keys'
require_not_contains_anywhere 'top-level settings keys'
require_not_contains_anywhere 'user-added settings keys'
require_not_contains_anywhere 'state schema version is `3`'

if command -v nix >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  flake_ref="path:$ROOT"
  manifest_json="$(
    nix eval --json "${flake_ref}#darwinConfigurations" \
      --impure \
      --apply 'targets: (import ./nix/scripts/targets-manifest.nix {}).json targets'
  )"

  while IFS=$'\t' read -r host default_rice; do
    require_contains_file docs/commands.md "\`${host}\` (default rice: \`${default_rice}\`)"
  done < <(
    printf '%s' "$manifest_json" |
      jq -r '.hosts | to_entries[] | "\(.key)\t\(.value.defaultRice)"'
  )
fi

echo "PASS: docs consistency"
