#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOTFILES_SCRIPT="$ROOT/nix/scripts/dotfiles.sh"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"

if [[ ! -f $DOTFILES_SCRIPT ]]; then
  echo "test: dotfiles script not found: $DOTFILES_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

tmp_stdout="$(mktemp)"
tmp_stderr="$(mktemp)"
cleanup() {
  rm -f "$tmp_stdout" "$tmp_stderr"
}
trap cleanup EXIT

if bash "$DOTFILES_SCRIPT" shell sync --check >"$tmp_stdout" 2>"$tmp_stderr"; then
  echo "FAIL: legacy shell CLI unexpectedly succeeded" >&2
  exit 1
fi

if ! grep -Fq 'unknown subcommand: shell' "$tmp_stderr"; then
  echo "FAIL: legacy shell CLI did not report unknown subcommand" >&2
  cat "$tmp_stderr" >&2 || true
  exit 1
fi

if ! grep -Fq 'sync' "$tmp_stderr"; then
  echo "FAIL: legacy shell CLI error did not point to new sync command" >&2
  cat "$tmp_stderr" >&2 || true
  exit 1
fi

help_output="$(bash "$SYNC_SCRIPT" --help 2>&1 || true)"
if [[ $help_output != *"sync <surface>"* ]]; then
  echo "FAIL: sync help missing surface usage" >&2
  printf '%s\n' "$help_output" >&2
  exit 1
fi

echo "PASS: sync CLI migration"
