#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: nix run .#apply -- [host]

Environment:
  HOST=...        Host to switch (default: a2m_mac)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles-local)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles-secrets)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles-local)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles-secrets)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$ROOT" ]]; then
  echo "apply: not in a git repository" >&2
  exit 1
fi

cd "$ROOT"

HOST="${1:-${HOST:-a2m_mac}}"
FACTS_DIR="${FACTS_DIR:-$HOME/.config/dotfiles-local}"
SECRETS_DIR="${SECRETS_DIR:-$HOME/.config/dotfiles-secrets}"
FACTS="${FACTS:-path:${FACTS_DIR}}"
SECRETS="${SECRETS:-path:${SECRETS_DIR}}"

if command -v darwin-rebuild >/dev/null 2>&1; then
  rebuild_cmd=(darwin-rebuild)
else
  rebuild_cmd=(nix run github:nix-darwin/nix-darwin#darwin-rebuild --)
fi

rebuild_args=(switch
  --flake "$ROOT#${HOST}"
  --override-input local "$FACTS"
  --override-input secrets "$SECRETS"
)

if [[ "$EUID" -eq 0 ]]; then
  "${rebuild_cmd[@]}" "${rebuild_args[@]}"
else
  sudo -E "${rebuild_cmd[@]}" "${rebuild_args[@]}"
fi
