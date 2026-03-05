#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="apply"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#apply -- [--host <host>] [--rice <rice>] [--action switch|build] [--no-sudo] [--] [darwin-rebuild args...]
       nix run .#apply -- [host]

Environment:
  HOST=...        Host to switch (default: a2m_mac)
  RICE=...        Rice to apply (default: none)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles)
USAGE
}

host=""
rice=""
action="switch"
no_sudo=0
passthrough=()

if [[ $# -gt 0 ]]; then
  case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  esac
fi

PARSE_TARGET_VALUE_OPTIONS="--action"
parse_target_args "$@"
unset PARSE_TARGET_VALUE_OPTIONS

host="$PARSED_HOST"
rice="$PARSED_RICE"
passthrough=("${PARSED_PASSTHROUGH[@]}")

idx=0
while [[ $idx -lt ${#PARSED_ARGS[@]} ]]; do
  arg="${PARSED_ARGS[$idx]}"
  case "$arg" in
  --action)
    idx=$((idx + 1))
    [[ $idx -lt ${#PARSED_ARGS[@]} ]] || die "missing value for --action"
    action="${PARSED_ARGS[$idx]}"
    ;;
  --no-sudo)
    no_sudo=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    die "unknown option: $arg"
    ;;
  *)
    die "unexpected argument: $arg (use -- to pass through to darwin-rebuild)"
    ;;
  esac
  idx=$((idx + 1))
done

host="${host:-${HOST:-a2m_mac}}"
rice="${rice:-${RICE:-}}"

case "$action" in
switch | build) ;;
*) die "invalid --action: $action (expected switch or build)" ;;
esac

set_repo_root
cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1

if command -v darwin-rebuild >/dev/null 2>&1; then
  rebuild_cmd=(darwin-rebuild)
else
  darwin_rebuild_bin="$(nix build --no-link --print-out-paths nix-darwin#darwin-rebuild)/bin/darwin-rebuild"
  rebuild_cmd=("$darwin_rebuild_bin")
fi

rebuild_args=("$action"
  --flake "${flake_ref}#${target}"
  --override-input local "$FACTS"
  --override-input secrets "$SECRETS"
)

if [[ ${#passthrough[@]} -gt 0 ]]; then
  rebuild_args+=("${passthrough[@]}")
fi

if [[ $EUID -eq 0 || $no_sudo -eq 1 ]]; then
  "${rebuild_cmd[@]}" "${rebuild_args[@]}"
else
  sudo -E "${rebuild_cmd[@]}" "${rebuild_args[@]}"
fi
