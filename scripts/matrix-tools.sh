#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="matrix-tools"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#matrix-tools -- [--format json|text] [--full]

Environment:
  FORMAT=...      Output format (json or text; default: text)
  FACTS_DIR=...   Local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Local secrets dir (default: $HOME/.config/dotfiles)
  FACTS=...       Advanced local input override (default: path:$FACTS_DIR)
  SECRETS=...     Advanced secrets input override (default: path:$SECRETS_DIR)
USAGE
}

format=""
full=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --format)
    [[ $# -lt 2 ]] && die "missing value for --format"
    format="$2"
    shift 2
    ;;
  --full)
    full=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    die "unknown option: $1"
    ;;
  *)
    die "unexpected argument: $1"
    ;;
  esac
done

format="${format:-${FORMAT:-text}}"

case "$format" in
json | text) ;;
*) die "invalid --format: $format (expected json or text)" ;;
esac

set_repo_root
cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

if ! targets=$(list_darwin_targets "$ROOT" "$FACTS" "$SECRETS"); then
  log "unable to evaluate darwinConfigurations (check local/secrets inputs and STUB)"
  log_darwin_configuration_hints "$FACTS" "$SECRETS"
  exit 1
fi

if [[ -z $targets ]]; then
  log "no darwinConfigurations found (check local/secrets inputs and STUB)"
  log_darwin_configuration_hints "$FACTS" "$SECRETS"
  exit 1
fi

tools_expr_path="./nix/scripts/matrix-tools.nix"
full_literal="false"
if [[ $full -eq 1 ]]; then
  full_literal="true"
fi

if [[ $format == "json" ]]; then
  nix eval --json "$flake_ref#darwinConfigurations" \
    --no-update-lock-file \
    --impure \
    --apply "targets: (import ${tools_expr_path} { full = ${full_literal}; }).json targets" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS"
  printf '\n'
  exit 0
fi

nix eval --raw "$flake_ref#darwinConfigurations" \
  --no-update-lock-file \
  --impure \
  --apply "targets: (import ${tools_expr_path} { full = ${full_literal}; }).text targets" \
  --override-input local "$FACTS" \
  --override-input secrets "$SECRETS"
printf '\n'
