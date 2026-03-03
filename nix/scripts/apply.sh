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

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
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
  --action)
    [[ $# -lt 2 ]] && die "missing value for --action"
    action="$2"
    shift 2
    ;;
  --no-sudo)
    no_sudo=1
    shift
    ;;
  --)
    shift
    passthrough=("$@")
    break
    ;;
  --*)
    die "unknown option: $1"
    ;;
  *)
    if [[ -z $host ]]; then
      host="$1"
      shift
    else
      die "unexpected argument: $1 (use -- to pass through to darwin-rebuild)"
    fi
    ;;
  esac
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

target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1

if command -v darwin-rebuild >/dev/null 2>&1; then
  rebuild_cmd=(darwin-rebuild)
else
  darwin_rebuild_bin="$(nix build --no-link --print-out-paths nix-darwin#darwin-rebuild)/bin/darwin-rebuild"
  rebuild_cmd=("$darwin_rebuild_bin")
fi

rebuild_args=("$action"
  --flake "$ROOT#${target}"
  --override-input local "$FACTS"
  --override-input secrets "$SECRETS"
)

if [[ ${#passthrough[@]} -gt 0 ]]; then
  rebuild_args+=("${passthrough[@]}")
fi

force_import_flag="/tmp/dotfiles-terminal-force-import"
if [[ ${DOTFILES_TERMINAL_FORCE_IMPORT:-0} == "1" ]]; then
  printf '1\n' >"$force_import_flag"
  chmod 0644 "$force_import_flag" >/dev/null 2>&1 || true
  trap 'rm -f "$force_import_flag"' EXIT
fi

if [[ $EUID -eq 0 || $no_sudo -eq 1 ]]; then
  "${rebuild_cmd[@]}" "${rebuild_args[@]}"
else
  sudo -E "${rebuild_cmd[@]}" "${rebuild_args[@]}"
fi
