#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'USAGE'
Usage: nix run .#dotfiles -- <subcommand> [args...]

Subcommands:
  apply
  update
  doctor
  bootstrap
  migrate-state
  list-tools
  terminal
  shell
USAGE
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
apply | update | doctor | bootstrap | migrate-state | list-tools | terminal | shell)
  target="$SCRIPT_DIR/${subcommand}.sh"
  if [[ ! -f $target ]]; then
    cwd_target="$(pwd)/nix/scripts/${subcommand}.sh"
    if [[ -f $cwd_target ]]; then
      target="$cwd_target"
    else
      echo "dotfiles: subcommand script not found: $target" >&2
      exit 1
    fi
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
