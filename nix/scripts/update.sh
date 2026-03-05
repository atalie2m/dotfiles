#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="update"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#update -- [--host <host>] [--rice <rice>]
       nix run .#update -- [host]

Environment:
  HOST=...                Host to build (default: a2m_mac)
  RICE=...                Rice to build (default: none)
  FACTS=...               Full local facts input (default: path:$HOME/.config/dotfiles)
  SECRETS=...             Full local secrets input (default: path:$HOME/.config/dotfiles)
  FACTS_DIR=...           Override local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=...         Override local secrets dir (default: $HOME/.config/dotfiles)
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

host="${host:-${HOST:-a2m_mac}}"
rice="${rice:-${RICE:-}}"
start_dir="$PWD"

set_repo_root
ROOT="$(require_writable_checkout "$ROOT" "$start_dir")"

cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

update_inputs=(
  nixpkgs
  nix-darwin
  home-manager
  denix
  sops-nix
  brew-nix
  brew-api
  mac-app-util
)

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
  if command -v darwin-rebuild >/dev/null 2>&1; then
    darwin-rebuild "$@"
  else
    if [[ -z ${DARWIN_REBUILD_BIN:-} ]]; then
      DARWIN_REBUILD_BIN="$(nix build --no-link --print-out-paths nix-darwin#darwin-rebuild)/bin/darwin-rebuild"
    fi
    "$DARWIN_REBUILD_BIN" "$@"
  fi
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

if [[ ${UPDATE_SKIP_BUILD:-0} != "1" ]]; then
  target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1
  darwin_rebuild build \
    --flake "${flake_ref}#${target}" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ ${UPDATE_COMMIT:-0} == "1" ]]; then
  if git diff --quiet && git diff --cached --quiet; then
    echo "update: no changes to commit"
  else
    git add flake.lock
    git commit -m "chore(update): flake inputs"
  fi
fi
