#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="doctor"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"
# shellcheck source=doctor/lib.sh
source "$SCRIPT_DIR/doctor/lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#doctor -- [--host <host>] [--rice <rice>] [--strict] [--json]

Environment:
  HOST=...        Host to inspect (default: none)
  RICE=...        Rice to inspect (default: none)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles)
USAGE
}

host=""
rice=""
strict=0
json=0
resolved_target=""

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
  --strict)
    strict=1
    ;;
  --json)
    json=1
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
done

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"

set_repo_root
cd "$ROOT"
resolve_inputs
flake_ref="$(flake_ref_for_root "$ROOT")"

CHECK_NAMES=()
CHECK_STATUS=()
CHECK_MESSAGE=()
FAILURES=0
WARNINGS=0

record_check() {
  local name="$1"
  local status="$2"
  local message="$3"

  CHECK_NAMES+=("$name")
  CHECK_STATUS+=("$status")
  CHECK_MESSAGE+=("$message")

  case "$status" in
  fail) FAILURES=$((FAILURES + 1)) ;;
  warn) WARNINGS=$((WARNINGS + 1)) ;;
  esac

  if [[ $json -eq 0 ]]; then
    printf '%-5s %s: %s\n' "$status" "$name" "$message"
  fi
}

record_facts_checks
record_basic_system_checks
record_target_checks

if [[ $strict -eq 1 ]]; then
  if nix flake check "$flake_ref" \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS" \
    >/dev/null 2>&1; then
    record_check "flake.check" "ok" "nix flake check passed"
  else
    record_check "flake.check" "fail" "nix flake check failed"
  fi

  if [[ $(uname -s 2>/dev/null || true) == "Darwin" ]]; then
    record_strict_sync_checks
  else
    record_check "terminal.sync" "ok" "skipped on non-Darwin host"
    record_check "shell.sync" "ok" "skipped on non-Darwin host"
  fi
fi

if [[ $json -eq 1 ]]; then
  ok="false"
  if [[ $FAILURES -eq 0 ]]; then
    ok="true"
  fi

  printf '{'
  printf '"ok":%s,' "$ok"
  printf '"failures":%s,' "$FAILURES"
  printf '"warnings":%s,' "$WARNINGS"
  printf '"checks":['
  for i in "${!CHECK_NAMES[@]}"; do
    name=$(json_escape "${CHECK_NAMES[$i]}")
    status=$(json_escape "${CHECK_STATUS[$i]}")
    message=$(json_escape "${CHECK_MESSAGE[$i]}")
    printf '{"name":"%s","status":"%s","message":"%s"}' "$name" "$status" "$message"
    if [[ $i -lt $((${#CHECK_NAMES[@]} - 1)) ]]; then
      printf ','
    fi
  done
  printf ']}\n'
fi

if [[ $FAILURES -eq 0 ]]; then
  exit 0
fi
exit 1
