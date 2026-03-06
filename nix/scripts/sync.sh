#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="sync"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- sync <surface> [options]

Surfaces:
  shell      Keep writable shell entrypoints aligned with managed blocks/files
  terminal   Reconcile Terminal.app profiles

Shell usage:
  nix run .#dotfiles -- sync shell --check [--details] [--diff] [--group <zsh|bash|fish|all>] [--item <id>] [--managed-dir <path>]
  nix run .#dotfiles -- sync shell --apply [--details] [--diff] [--group <zsh|bash|fish|all>] [--item <id>] [--managed-dir <path>]

Terminal usage:
  nix run .#dotfiles -- sync terminal --check [--details] [--diff] [--item <name>] [--profiles-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- sync terminal --apply [--details] [--diff] [--item <name>] [--profiles-dir <path>] [--state-dir <path>] [--force] [--default-profile <name>] [--startup-profile <name>]
  nix run .#dotfiles -- sync terminal --adopt [--details] [--diff] [--item <name>] [--profiles-dir <path>] [--state-dir <path>] [--in-place] [--force] [--output-dir <path>]
  nix run .#dotfiles -- sync terminal --forget [--item <name>] [--profiles-dir <path>] [--state-dir <path>]
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

surface="$1"
shift

case "$surface" in
shell | terminal)
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
  die "unknown sync surface: $surface (expected: shell, terminal)"
  ;;
esac
