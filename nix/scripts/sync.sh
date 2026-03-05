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
  shell      Reconcile shell managed blocks/files
  terminal   Reconcile Terminal.app profiles

Common options:
  --check --apply --adopt --forget --details --diff --in-place --force --output-dir <path> --item <id> --state-dir <path>

Shell-specific options:
  --group <zsh|bash|fish|all> --managed-dir <path> --migrate

Terminal-specific options:
  --profiles-dir <path> --default-profile <name> --startup-profile <name>
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
