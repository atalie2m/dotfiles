#!/usr/bin/env bash
set -euo pipefail

ADAPTER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_RUST_BIN="$ADAPTER_DIR/vscode-rs/bin/dotfiles-sync-vscode"

if [[ -n ${DOTFILES_SYNC_VSCODE_BIN:-} ]]; then
  if [[ ! -x "$DOTFILES_SYNC_VSCODE_BIN" ]]; then
    printf 'sync-vscode: configured Rust binary is not executable: %s\n' "$DOTFILES_SYNC_VSCODE_BIN" >&2
    exit 1
  fi
  exec "$DOTFILES_SYNC_VSCODE_BIN" "$@"
fi

if [[ -x $DEFAULT_RUST_BIN ]]; then
  exec "$DEFAULT_RUST_BIN" "$@"
fi

if command -v dotfiles-sync-vscode >/dev/null 2>&1; then
  exec "$(command -v dotfiles-sync-vscode)" "$@"
fi

printf 'sync-vscode: dotfiles-sync-vscode binary not found (expected DOTFILES_SYNC_VSCODE_BIN, %s, or PATH entry)\n' "$DEFAULT_RUST_BIN" >&2
exit 1
