#!/usr/bin/env bash
set -euo pipefail

ADAPTER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LEGACY_ADAPTER="$ADAPTER_DIR/vscode-legacy.sh"
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

if [[ ! -f $LEGACY_ADAPTER ]]; then
  printf 'sync-vscode: legacy adapter not found: %s\n' "$LEGACY_ADAPTER" >&2
  exit 1
fi

exec bash "$LEGACY_ADAPTER" "$@"
