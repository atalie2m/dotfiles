#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${DOTFILES_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

if [[ $# -lt 1 ]]; then
  echo "dotfiles: missing subcommand for shim" >&2
  exit 1
fi

if [[ -n ${DOTFILES_BIN:-} && -x ${DOTFILES_BIN} ]]; then
  export DOTFILES_ROOT="$ROOT"
  exec "${DOTFILES_BIN}" "$@"
fi

PROFILE_DOTFILES="${HOME:-}/.nix-profile/bin/dotfiles"
if [[ -x "$PROFILE_DOTFILES" ]]; then
  export DOTFILES_ROOT="$ROOT"
  exec "$PROFILE_DOTFILES" "$@"
fi

if command -v dotfiles >/dev/null 2>&1; then
  export DOTFILES_ROOT="$ROOT"
  exec "$(command -v dotfiles)" "$@"
fi

echo "dotfiles: unable to locate the Rust CLI binary (set DOTFILES_BIN or install dotfiles in PATH)" >&2
exit 1
