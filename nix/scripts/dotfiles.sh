#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ ! -f "$SCRIPT_DIR/apply.sh" ]]; then
  if git_root=$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null); then
    if [[ -f "$git_root/nix/scripts/apply.sh" ]]; then
      SCRIPT_DIR="$git_root/nix/scripts"
    fi
  fi
fi

usage() {
  cat <<'USAGE'
Usage: nix run .#dotfiles -- <subcommand> [args...]

Subcommands:
  apply
  update
  doctor
  bootstrap
  list-tools
USAGE
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
apply | update | doctor | bootstrap | list-tools)
  target="$SCRIPT_DIR/${subcommand}.sh"
  if [[ ! -f $target ]]; then
    echo "dotfiles: subcommand script not found: $target" >&2
    exit 1
  fi
  exec "$target" "$@"
  ;;
help | -h | --help)
  usage
  ;;
*)
  echo "dotfiles: unknown subcommand: $subcommand" >&2
  usage >&2
  exit 1
  ;;
esac
