#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="list-tools"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#list-tools -- [--host <host>] [--rice <rice>] [--format json|text]
       nix run .#list-tools -- [host]

Environment:
  HOST=...        Host to inspect (default: none)
  RICE=...        Rice to inspect (default: none)
  FORMAT=...      Output format (json or text; default: text)
  FACTS_DIR=...   Local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Local secrets dir (default: $HOME/.config/dotfiles)
  FACTS=...       Advanced local input override (default: path:$FACTS_DIR)
  SECRETS=...     Advanced secrets input override (default: path:$SECRETS_DIR)
USAGE
}

host=""
rice=""
format=""

if [[ $# -gt 0 ]]; then
  case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  esac
fi

export PARSE_TARGET_VALUE_OPTIONS="--format"
parse_target_args "$@"
unset PARSE_TARGET_VALUE_OPTIONS

if [[ $PARSED_HAS_PASSTHROUGH -eq 1 ]]; then
  die "unexpected -- (no passthrough supported)"
fi

host="$PARSED_HOST"
rice="$PARSED_RICE"

idx=0
while [[ $idx -lt ${#PARSED_ARGS[@]} ]]; do
  arg="${PARSED_ARGS[$idx]}"
  case "$arg" in
  --format)
    idx=$((idx + 1))
    [[ $idx -lt ${#PARSED_ARGS[@]} ]] || die "missing value for --format"
    format="${PARSED_ARGS[$idx]}"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    die "unknown option: $arg"
    ;;
  *)
    die "unexpected argument: $arg"
    ;;
  esac
  idx=$((idx + 1))
done

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"
format="${format:-${FORMAT:-text}}"
require_host_argument "$host" "list-tools"

case "$format" in
json | text) ;;
*) die "invalid --format: $format (expected json or text)" ;;
esac

set_repo_root
cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1

attr="${flake_ref}#darwinConfigurations.${target}.config"
tools_expr_path="./nix/scripts/list-tools.nix"

if [[ $format == "json" ]]; then
  nix eval --json "$attr" \
    --no-update-lock-file \
    --impure \
    --apply "cfg: (import ${tools_expr_path} { }).select cfg" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
  printf '\n'
  exit 0
fi

nix eval --raw "$attr" \
  --no-update-lock-file \
  --impure \
  --apply "cfg: (import ${tools_expr_path} { }).text cfg" \
  --override-input local "$FACTS" \
  --override-input secrets "$SECRETS"
printf '\n'
