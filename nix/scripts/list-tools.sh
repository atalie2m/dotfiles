#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="list-tools"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#list-tools -- [--host <host>] [--rice <rice>] [--format json|text]
       nix run .#list-tools -- [host]

Environment:
  HOST=...        Host to inspect (default: a2m_mac)
  RICE=...        Rice to inspect (default: none)
  FORMAT=...      Output format (json or text; default: text)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles)
USAGE
}

host=""
rice=""
format=""

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
  --format)
    [[ $# -lt 2 ]] && die "missing value for --format"
    format="$2"
    shift 2
    ;;
  --*)
    die "unknown option: $1"
    ;;
  *)
    if [[ -z $host ]]; then
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
format="${format:-${FORMAT:-text}}"

case "$format" in
json | text) ;;
*) die "invalid --format: $format (expected json or text)" ;;
esac

set_repo_root
cd "$ROOT"
resolve_inputs

target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS") || exit 1

attr="$ROOT#darwinConfigurations.${target}.config"
tools_expr_path="./nix/scripts/list-tools.nix"

if [[ $format == "json" ]]; then
  nix eval --json "$attr" \
    --impure \
    --apply "cfg: (import ${tools_expr_path} { }).select cfg" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
  printf '\n'
  exit 0
fi

nix eval --raw "$attr" \
  --impure \
  --apply "cfg: (import ${tools_expr_path} { }).text cfg" \
  --override-input local "$FACTS" \
  --override-input secrets "$SECRETS"
printf '\n'
