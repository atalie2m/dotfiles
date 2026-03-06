#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
SOURCE_MANAGED_DIR="$ROOT/surfaces/shell/desired"

if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-cli-common.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

shell_home="$tmp_root/shell-home"
shell_managed="$tmp_root/shell-managed"

mkdir -p "$shell_home"
cp -R "$SOURCE_MANAGED_DIR" "$shell_managed"
chmod -R u+w "$shell_managed"

run_shell_sync() {
  HOME="$shell_home" bash "$SYNC_SCRIPT" shell "$@" --managed-dir "$shell_managed"
}

printf 'test: running sync cli common parse test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: shell apply failed" >&2
  exit 1
fi
if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: shell check failed after apply" >&2
  exit 1
fi

missing_item="missing-parse-item"
if run_shell_sync --check --item "$missing_item" >/dev/null 2>"$tmp_root/shell.err"; then
  echo "FAIL: shell check unexpectedly passed for missing --item" >&2
  exit 1
fi
if ! grep -Fq "no item matched --item '$missing_item'" "$tmp_root/shell.err"; then
  echo "FAIL: shell missing-item message did not use expected wording" >&2
  exit 1
fi

for removed in --migrate --adopt --forget --state-dir --force --in-place --output-dir; do
  case "$removed" in
  --state-dir | --output-dir)
    if run_shell_sync "$removed" "$tmp_root/unused" >/dev/null 2>"$tmp_root/${removed#--}.err"; then
      echo "FAIL: shell unexpectedly accepted removed option $removed" >&2
      exit 1
    fi
    ;;
  *)
    if run_shell_sync "$removed" >/dev/null 2>"$tmp_root/${removed#--}.err"; then
      echo "FAIL: shell unexpectedly accepted removed option $removed" >&2
      exit 1
    fi
    ;;
  esac
  if ! grep -Fq -- "$removed is no longer supported for sync shell" "$tmp_root/${removed#--}.err"; then
    echo "FAIL: shell removed-option message missing for $removed" >&2
    cat "$tmp_root/${removed#--}.err" >&2 || true
    exit 1
  fi
done

if bash "$SYNC_SCRIPT" terminal --check >/dev/null 2>"$tmp_root/terminal.err"; then
  echo "FAIL: sync unexpectedly accepted removed terminal surface" >&2
  exit 1
fi
if ! grep -Fq "unknown sync surface: terminal (expected: shell)" "$tmp_root/terminal.err"; then
  echo "FAIL: removed terminal surface did not report expected error" >&2
  cat "$tmp_root/terminal.err" >&2 || true
  exit 1
fi

echo "PASS: sync cli common parse"
