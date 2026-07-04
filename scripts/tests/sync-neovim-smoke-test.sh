#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/scripts/sync.sh"
SOURCE_MANAGED_DIR="$ROOT/apps/neovim"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/sync-neovim-smoke-test.sh

Description:
  Runs a lightweight Neovim config sync smoke test with temporary managed,
  runtime, and state directories.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

if [[ ! -d $SOURCE_MANAGED_DIR ]]; then
  echo "test: Neovim managed dir not found: $SOURCE_MANAGED_DIR" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-neovim-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
managed_dir="$tmp_root/managed"
runtime_dir="$tmp_root/runtime-nvim"
state_dir="$tmp_root/state-nvim"

mkdir -p "$home_dir" "$runtime_dir" "$state_dir"
cp -R "$SOURCE_MANAGED_DIR" "$managed_dir"
chmod -R u+w "$managed_dir"

run_neovim_sync() {
  HOME="$home_dir" \
    bash "$SYNC_SCRIPT" neovim "$@" \
    --managed-dir "$managed_dir" \
    --runtime-dir "$runtime_dir" \
    --state-dir "$state_dir"
}

printf 'test: running Neovim sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_neovim_sync --apply >/dev/null; then
  echo "FAIL: initial apply failed" >&2
  exit 1
fi

if [[ ! -f $runtime_dir/init.lua ]]; then
  echo "FAIL: runtime init.lua was not materialized" >&2
  exit 1
fi

if [[ ! -f $state_dir/lazy-lock.json ]]; then
  echo "FAIL: lazy-lock.json was not materialized into state dir" >&2
  exit 1
fi

if ! run_neovim_sync --check >/dev/null; then
  echo "FAIL: check failed after initial apply" >&2
  exit 1
fi

printf '\n-- smoke drift\n' >>"$runtime_dir/init.lua"
if run_neovim_sync --check >/dev/null 2>"$tmp_root/config-drift.err"; then
  echo "FAIL: check unexpectedly passed after runtime config drift" >&2
  exit 1
fi

if ! run_neovim_sync --adopt >/dev/null; then
  echo "FAIL: adopt failed for runtime config drift" >&2
  exit 1
fi

if ! cmp -s "$managed_dir/init.lua" "$runtime_dir/init.lua"; then
  echo "FAIL: adopt did not copy runtime config drift into managed dir" >&2
  exit 1
fi

printf '{"smoke":"state-lock"}\n' >"$state_dir/lazy-lock.json"
if run_neovim_sync --check >/dev/null 2>"$tmp_root/lock-drift.err"; then
  echo "FAIL: check unexpectedly passed after state lock drift" >&2
  exit 1
fi

if ! run_neovim_sync --adopt >/dev/null; then
  echo "FAIL: adopt failed for state lock drift" >&2
  exit 1
fi

if ! grep -Fq '"smoke":"state-lock"' "$managed_dir/lazy-lock.json"; then
  echo "FAIL: adopt did not copy effective state lock into managed lazy-lock.json" >&2
  exit 1
fi

mkdir -p "$runtime_dir/lua"
printf 'return { smoke = true }\n' >"$runtime_dir/lua/runtime-only.lua"
if run_neovim_sync --check >/dev/null 2>"$tmp_root/runtime-only.err"; then
  echo "FAIL: check unexpectedly passed with runtime-only config" >&2
  exit 1
fi

if ! run_neovim_sync --adopt >/dev/null; then
  echo "FAIL: adopt failed for runtime-only config" >&2
  exit 1
fi

if [[ ! -f $managed_dir/lua/runtime-only.lua ]]; then
  echo "FAIL: adopt did not copy runtime-only config into managed dir" >&2
  exit 1
fi

if ! run_neovim_sync --check >/dev/null; then
  echo "FAIL: final check failed" >&2
  exit 1
fi

echo "PASS: Neovim sync smoke"
