#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${DOTFILES_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

if [[ $# -lt 1 ]]; then
  echo "dotfiles: missing subcommand for shim" >&2
  exit 1
fi

if [[ -n ${DOTFILES_BIN:-} && -x ${DOTFILES_BIN} ]]; then
  exec "${DOTFILES_BIN}" "$@"
fi

if command -v dotfiles >/dev/null 2>&1; then
  exec "$(command -v dotfiles)" "$@"
fi

if command -v nix >/dev/null 2>&1; then
  exec nix run "path:${ROOT}#dotfiles" -- "$@"
fi

echo "dotfiles: unable to locate the Rust CLI binary or nix" >&2
exit 1
