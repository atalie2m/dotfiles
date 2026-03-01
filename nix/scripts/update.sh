#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_PATH="$SCRIPT_DIR/lib.sh"
if [[ ! -f "$LIB_PATH" ]]; then
  if git_root=$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null); then
    if [[ -f "$git_root/nix/scripts/lib.sh" ]]; then
      SCRIPT_DIR="$git_root/nix/scripts"
      LIB_PATH="$SCRIPT_DIR/lib.sh"
    fi
  fi
fi
if [[ ! -f "$LIB_PATH" ]]; then
  echo "update: lib.sh not found (tried $LIB_PATH)" >&2
  exit 1
fi
# shellcheck source=lib.sh
source "$LIB_PATH"

DOTFILES_SCRIPT_LABEL="update"

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
  UPDATE_FORMAT=1         Run formatter if available (best-effort)
USAGE
}

host=""
rice=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --host)
      [[ $# -lt 2 ]] && die "missing value for --host"
      host="$2"
      shift 2
      ;;
    --rice)
      [[ $# -lt 2 ]] && die "missing value for --rice"
      rice="$2"
      shift 2
      ;;
    --)
      die "unexpected -- (no passthrough supported)"
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      if [[ -z "$host" ]]; then
        host="$1"
        shift
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
done

host="${host:-${HOST:-a2m_mac}}"
rice="${rice:-${RICE:-}}"

set_repo_root
cd "$ROOT"
resolve_inputs

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

if [[ "${UPDATE_ALL:-0}" == "1" ]]; then
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
    nix run github:nix-darwin/nix-darwin#darwin-rebuild -- "$@"
  fi
}

if [[ "${UPDATE_FORMAT:-0}" == "1" ]]; then
  if nix run "$ROOT#format" -- --help >/dev/null 2>&1; then
    if ! nix run "$ROOT#format"; then
      log "formatter failed (continuing)"
    fi
  elif command -v treefmt >/dev/null 2>&1; then
    if ! treefmt; then
      log "treefmt failed (continuing)"
    fi
  else
    log "formatter not available (skipping UPDATE_FORMAT)"
  fi
fi

run_checks=1
if [[ "${UPDATE_SKIP_CHECK:-0}" == "1" && "${UPDATE_CHECKS:-0}" != "1" ]]; then
  run_checks=0
fi
if [[ "${UPDATE_CHECKS:-0}" == "1" ]]; then
  run_checks=1
fi

if [[ "$run_checks" -eq 1 ]]; then
  nix flake check \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ "${UPDATE_SKIP_BUILD:-0}" != "1" ]]; then
  target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1
  darwin_rebuild build \
    --flake "$ROOT#${target}" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ "${UPDATE_COMMIT:-0}" == "1" ]]; then
  if git diff --quiet && git diff --cached --quiet; then
    echo "update: no changes to commit"
  else
    git add flake.lock
    git commit -m "chore(update): flake inputs"
  fi
fi
