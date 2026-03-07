#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="update"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#update -- [--host <host>] [--rice <rice>]
       nix run .#update -- [host]

Environment:
  HOST=...                Host to build (default: none)
  RICE=...                Rice to build (default: none)
  FACTS_DIR=...           Local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=...         Local secrets dir (default: $HOME/.config/dotfiles)
  FACTS=...               Advanced local input override (default: path:$FACTS_DIR)
  SECRETS=...             Advanced secrets input override (default: path:$SECRETS_DIR)
  UPDATE_ALL=1            Update all flake inputs (default: selected inputs)
  UPDATE_SKIP_CHECK=1     Skip nix flake check
  UPDATE_SKIP_BUILD=1     Skip darwin-rebuild build
  UPDATE_COMMIT=1         Commit flake.lock after success
  UPDATE_CHECKS=1         Force nix flake check even if UPDATE_SKIP_CHECK=1
  UPDATE_FORMAT=1         Run repository formatter (nix run .#format)
USAGE
}

host=""
rice=""

if [[ $# -gt 0 ]]; then
  case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  esac
fi

parse_target_args "$@"
if [[ $PARSED_HAS_PASSTHROUGH -eq 1 ]]; then
  die "unexpected -- (no passthrough supported)"
fi

host="$PARSED_HOST"
rice="$PARSED_RICE"

if [[ ${#PARSED_ARGS[@]} -gt 0 ]]; then
  for arg in "${PARSED_ARGS[@]}"; do
    case "$arg" in
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
  done
fi

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"
start_dir="$PWD"

run_build=1
if [[ ${UPDATE_SKIP_BUILD:-0} == "1" ]]; then
  run_build=0
fi
if [[ $run_build -eq 1 ]]; then
  require_host_argument "$host" "update"
fi

set_repo_root
ROOT="$(require_writable_checkout "$ROOT" "$start_dir")"

cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

update_inputs=()
while IFS= read -r input || [[ -n $input ]]; do
  [[ -n $input ]] || continue
  update_inputs+=("$input")
done < <(list_updateable_root_flake_inputs "$ROOT")
if [[ ${#update_inputs[@]} -eq 0 ]]; then
  die "unable to determine updateable flake inputs from $ROOT/flake.lock"
fi

if [[ ${UPDATE_ALL:-0} == "1" ]]; then
  nix flake update
else
  update_args=()
  for input in "${update_inputs[@]}"; do
    update_args+=(--update-input "$input")
  done
  nix flake update "${update_args[@]}"
fi

darwin_rebuild() {
  local darwin_rebuild_bin
  darwin_rebuild_bin="$(resolve_pinned_darwin_rebuild_bin "$flake_ref")"
  "$darwin_rebuild_bin" "$@"
}

if [[ ${UPDATE_FORMAT:-0} == "1" ]]; then
  nix run "${flake_ref}#format"
fi

run_checks=1
if [[ ${UPDATE_SKIP_CHECK:-0} == "1" && ${UPDATE_CHECKS:-0} != "1" ]]; then
  run_checks=0
fi
if [[ ${UPDATE_CHECKS:-0} == "1" ]]; then
  run_checks=1
fi

if [[ $run_checks -eq 1 ]]; then
  nix flake check \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ $run_build -eq 1 ]]; then
  target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1
  darwin_rebuild build \
    --flake "${flake_ref}#${target}" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ ${UPDATE_COMMIT:-0} == "1" ]]; then
  if git diff --quiet -- flake.lock && git diff --cached --quiet -- flake.lock; then
    echo "update: no flake.lock changes to commit"
  else
    git add -- flake.lock
    git commit --only flake.lock -m "chore(update): flake inputs"
  fi
fi
