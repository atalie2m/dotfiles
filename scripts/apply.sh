#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="apply"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#apply -- [--host <host>] [--rice <rice>] [--action switch|build] [--no-sudo] [--] [darwin-rebuild args...]
       nix run .#apply -- [host]

Environment:
  HOST=...        Host to switch (default: none)
  RICE=...        Rice to apply (default: none)
  FACTS_DIR=...   Local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Local secrets dir (default: $HOME/.config/dotfiles)
  FACTS=...       Advanced local input override (default: path:$FACTS_DIR)
  SECRETS=...     Advanced secrets input override (default: path:$SECRETS_DIR)
USAGE
}

build_sudo_preserve_env() {
  local -a vars
  local var joined

  vars=(PATH)
  for var in FACTS FACTS_DIR SECRETS SECRETS_DIR DARWIN_REBUILD_BIN; do
    if [[ -n ${!var:-} ]]; then
      vars+=("$var")
    fi
  done

  joined="${vars[*]}"
  printf '%s\n' "${joined// /,}"
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

export PARSE_TARGET_VALUE_OPTIONS="--action"
parse_target_args "$@"
unset PARSE_TARGET_VALUE_OPTIONS

host="$PARSED_HOST"
rice="$PARSED_RICE"
if [[ ${PARSED_HAS_PASSTHROUGH:-0} -eq 1 ]]; then
  passthrough=("${PARSED_PASSTHROUGH[@]}")
fi

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

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"
require_host_argument "$host" "apply"

case "$action" in
switch | build) ;;
*) die "invalid --action: $action (expected switch or build)" ;;
esac

set_repo_root
cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1

darwin_rebuild_bin="$(resolve_pinned_darwin_rebuild_bin "$flake_ref")"
rebuild_cmd=("$darwin_rebuild_bin")

rebuild_args=("$action"
  --flake "${flake_ref}#${target}"
  --no-update-lock-file
  --override-input local "$FACTS"
  --override-input secrets "$SECRETS"
)

if [[ ${#passthrough[@]} -gt 0 ]]; then
  rebuild_args+=("${passthrough[@]}")
fi

if [[ $EUID -eq 0 || $no_sudo -eq 1 ]]; then
  "${rebuild_cmd[@]}" "${rebuild_args[@]}"
else
  sudo --preserve-env="$(build_sudo_preserve_env)" "${rebuild_cmd[@]}" "${rebuild_args[@]}"
fi
