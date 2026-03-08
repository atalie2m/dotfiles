#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="sync"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- sync <shell|vscode> [options]

Surface:
  shell      Keep writable shell entrypoints aligned with managed blocks/files
  vscode     Keep managed VS Code native profiles aligned with repo-managed settings/extensions

Shell usage:
  nix run .#dotfiles -- sync shell --check [--details] [--diff] [--group <zsh|bash|all>] [--item <id>] [--managed-dir <path>]
  nix run .#dotfiles -- sync shell --apply [--details] [--diff] [--group <zsh|bash|all>] [--item <id>] [--managed-dir <path>]

VS Code usage:
  nix run .#dotfiles -- sync vscode --check [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- sync vscode --apply [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

surface="$1"
shift

case "$surface" in
shell | vscode)
  adapter="$SCRIPT_DIR/sync-adapters/${surface}.sh"
  if [[ ! -f $adapter ]]; then
    die "sync adapter script not found: $adapter"
  fi
  exec bash "$adapter" "$@"
  ;;
help | -h | --help)
  usage
  exit 0
  ;;
*)
  die "unknown sync surface: $surface (expected: shell or vscode)"
  ;;
esac
