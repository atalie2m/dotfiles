#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

EN_DOC_FILES=(
  README.md
  docs/commands.md
  docs/reconciled-surfaces.md
  docs/architecture-reset.md
  docs/architecture.md
  docs/vscode.md
  docs/homebrew-policy.md
  docs/secrets-local.md
  docs/tool-catalog.md
  AGENTS.md
  CLAUDE.md
)

JA_DOC_FILES=(
  docs/ja/README.md
  docs/ja/commands.md
  docs/ja/reconciled-surfaces.md
  docs/ja/architecture-reset.md
  docs/ja/architecture.md
  docs/ja/vscode.md
  docs/ja/homebrew-policy.md
  docs/ja/secrets-local.md
  docs/ja/tool-catalog.md
  docs/ja/AGENTS.md
  docs/ja/CLAUDE.md
)

DOC_LINK_PAIRS=(
  $'README.md\tdocs/ja/README.md\t[日本語版はこちら](docs/ja/README.md)\t[English version](../../README.md)'
  $'docs/commands.md\tdocs/ja/commands.md\t[日本語版はこちら](ja/commands.md)\t[English version](../commands.md)'
  $'docs/reconciled-surfaces.md\tdocs/ja/reconciled-surfaces.md\t[日本語版はこちら](ja/reconciled-surfaces.md)\t[English version](../reconciled-surfaces.md)'
  $'docs/architecture-reset.md\tdocs/ja/architecture-reset.md\t[日本語版はこちら](ja/architecture-reset.md)\t[English version](../architecture-reset.md)'
  $'docs/architecture.md\tdocs/ja/architecture.md\t[日本語版はこちら](ja/architecture.md)\t[English version](../architecture.md)'
  $'docs/vscode.md\tdocs/ja/vscode.md\t[日本語版はこちら](ja/vscode.md)\t[English version](../vscode.md)'
  $'docs/homebrew-policy.md\tdocs/ja/homebrew-policy.md\t[日本語版はこちら](ja/homebrew-policy.md)\t[English version](../homebrew-policy.md)'
  $'docs/secrets-local.md\tdocs/ja/secrets-local.md\t[日本語版はこちら](ja/secrets-local.md)\t[English version](../secrets-local.md)'
  $'docs/tool-catalog.md\tdocs/ja/tool-catalog.md\t[日本語版はこちら](ja/tool-catalog.md)\t[English version](../tool-catalog.md)'
  $'AGENTS.md\tdocs/ja/AGENTS.md\t[日本語版はこちら](docs/ja/AGENTS.md)\t[English version](../../AGENTS.md)'
  $'CLAUDE.md\tdocs/ja/CLAUDE.md\t[日本語版はこちら](docs/ja/CLAUDE.md)\t[English version](../../CLAUDE.md)'
)

require_contains_anywhere() {
  local expected="$1"
  local found=0
  local file
  for file in "${EN_DOC_FILES[@]}"; do
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
  for file in "${EN_DOC_FILES[@]}"; do
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

require_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: expected file missing: $file" >&2
    exit 1
  fi
}

for file in "${EN_DOC_FILES[@]}" "${JA_DOC_FILES[@]}"; do
  require_file_exists "$file"
done

for pair in "${DOC_LINK_PAIRS[@]}"; do
  IFS=$'\t' read -r en_file ja_file en_link ja_link <<<"$pair"
  require_contains_file "$en_file" "$en_link"
  require_contains_file "$ja_file" "$ja_link"
done

require_contains_anywhere 'darwinConfigurations'
require_contains_anywhere 'nix run .#dotfiles -- sync shell'
require_contains_anywhere 'nix run .#dotfiles -- sync vscode'
require_contains_anywhere 'dotfiles-sync-vscode'
require_contains_anywhere 'activation skips cleanly'
require_contains_file docs/commands.md '## Runtime overrides'
require_contains_file docs/commands.md '`DOTFILES_SYNC_VSCODE_BIN` overrides the `sync vscode` engine path.'

require_contains_file README.md 'managed profile settings are fully repo-owned'
require_contains_file docs/reconciled-surfaces.md 'managed profile settings files converge fully to the repo state'
require_contains_file docs/vscode.md 'manual settings changes inside a managed profile are overwritten on the next apply'
require_contains_file docs/vscode.md 'VS Code'\''s built-in `Default` profile is intentionally unmanaged'
require_contains_file docs/commands.md 'These commands are Darwin-only and resolve `darwinConfigurations`.'

for file in "${EN_DOC_FILES[@]}"; do
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

  while IFS= read -r rice; do
    require_contains_file docs/commands.md "\`${rice}\`"
  done < <(
    printf '%s' "$manifest_json" |
      jq -r '[.hosts | to_entries[] | .value.supportedRices[]] | unique[]'
  )
fi

echo "PASS: docs consistency"
