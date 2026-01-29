#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: nix run .#update -- [host]

Environment:
  HOST=...                Host to build (default: a2m_mac)
  FACTS=...               Full local facts input (default: path:$HOME/.config/dotfiles-local)
  SECRETS=...             Full local secrets input (default: path:$HOME/.config/dotfiles-secrets)
  FACTS_DIR=...           Override local facts dir (default: $HOME/.config/dotfiles-local)
  SECRETS_DIR=...         Override local secrets dir (default: $HOME/.config/dotfiles-secrets)
  UPDATE_ALL=1            Update all flake inputs (default: selected inputs)
  UPDATE_SKIP_CHECK=1     Skip nix flake check
  UPDATE_SKIP_BUILD=1     Skip darwin-rebuild build
  UPDATE_COMMIT=1         Commit flake.lock + nvfetcher sources after success
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$ROOT" ]]; then
  echo "update: not in a git repository" >&2
  exit 1
fi

cd "$ROOT"

HOST="${1:-${HOST:-a2m_mac}}"
FACTS_DIR="${FACTS_DIR:-$HOME/.config/dotfiles-local}"
SECRETS_DIR="${SECRETS_DIR:-$HOME/.config/dotfiles-secrets}"
FACTS="${FACTS:-path:${FACTS_DIR}}"
SECRETS="${SECRETS:-path:${SECRETS_DIR}}"

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

if [[ -f "$ROOT/nix/nvfetcher/sources.toml" ]]; then
  nix run nixpkgs#nvfetcher -- \
    -c "$ROOT/nix/nvfetcher/sources.toml" \
    -o "$ROOT/nix/nvfetcher/_sources"
fi

darwin_rebuild() {
  if command -v darwin-rebuild >/dev/null 2>&1; then
    darwin-rebuild "$@"
  else
    nix run github:nix-darwin/nix-darwin#darwin-rebuild -- "$@"
  fi
}

if [[ "${UPDATE_SKIP_CHECK:-0}" != "1" ]]; then
  nix flake check \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ "${UPDATE_SKIP_BUILD:-0}" != "1" ]]; then
  darwin_rebuild build \
    --flake "$ROOT#${HOST}" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
fi

if [[ "${UPDATE_COMMIT:-0}" == "1" ]]; then
  if git diff --quiet && git diff --cached --quiet; then
    echo "update: no changes to commit"
  else
    git add flake.lock nix/nvfetcher/_sources
    git commit -m "chore(update): flake inputs and nvfetcher sources"
  fi
fi
