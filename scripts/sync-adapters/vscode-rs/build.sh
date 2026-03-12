#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR="$SCRIPT_DIR/bin"

cargo build --release --manifest-path "$SCRIPT_DIR/Cargo.toml"
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/target/release/dotfiles-sync-vscode" "$BIN_DIR/dotfiles-sync-vscode"
chmod +x "$BIN_DIR/dotfiles-sync-vscode"
