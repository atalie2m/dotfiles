#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="sync-core-test"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"
# shellcheck source=sync-core.sh
source "$SCRIPT_DIR/sync-core.sh"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-core-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

desired_file="$tmp_root/desired.txt"
actual_file="$tmp_root/actual.txt"
state_dir="$tmp_root/state"
out_dir="$tmp_root/out"

pass_count=0
fail_count=0

pass() {
  printf 'PASS: %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf 'FAIL: %s - %s\n' "$1" "$2" >&2
  fail_count=$((fail_count + 1))
}

sha_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  if [[ $expected != "$actual" ]]; then
    return 1
  fi
  return 0
}

run_core() {
  local mode="$1"
  local in_place="$2"
  local force="$3"
  local item_filter="${4:-}"

  sync_core_mode="$mode"
  sync_core_details=0
  sync_core_show_diff=0
  sync_core_in_place="$in_place"
  sync_core_force="$force"
  sync_core_output_dir="$out_dir"
  sync_core_item_filter="$item_filter"
  sync_core_root="$tmp_root"
  sync_core_state_dir="$state_dir"
  sync_core_staging_subdir="fake-adopt"
  sync_core_invalid_desired_status="invalid-desired"
  sync_core_invalid_actual_status="actual-invalid"
  sync_core_error_status="error"
  sync_core_invalid_seed=0
  sync_core_forget_invalid_seed=0

  sync_core_run
}

sync_adapter_list_items() {
  printf 'demo|%s|%s\n' "$desired_file" "$actual_file"
}

sync_adapter_extract_desired() {
  local _id="$1"
  local out="$2"
  cat "$desired_file" >"$out"
}

sync_adapter_extract_actual() {
  local _id="$1"
  local out="$2"

  if [[ ! -f $actual_file ]]; then
    return 2
  fi

  cat "$actual_file" >"$out"
}

sync_adapter_write_desired_to_actual() {
  cp "$desired_file" "$actual_file"
}

sync_adapter_export_actual() {
  local _id="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  cp "$actual_file" "$destination"
}

sync_adapter_stage_basename() {
  printf '%s\n' "demo.txt"
}

sync_adapter_stage_fallback_basename() {
  printf '%s\n' "demo-fallback.txt"
}

sync_adapter_inplace_destination() {
  local _id="$1"
  local desired_meta="$2"
  printf '%s\n' "$desired_meta"
}

sync_adapter_log_status() {
  return 0
}

sync_adapter_log_action() {
  return 0
}

test_apply_safe_update() {
  local name="apply-safe-update"
  mkdir -p "$state_dir"

  printf 'alpha\n' >"$actual_file"
  printf 'beta\n' >"$desired_file"
  printf '%s\n' "$(sha_file "$actual_file")" >"$state_dir/demo.sha256"

  if ! run_core apply 0 0; then
    fail "$name" "apply mode returned non-zero"
    return
  fi

  if ! diff -u "$desired_file" "$actual_file" >/dev/null 2>&1; then
    fail "$name" "actual content was not updated"
    return
  fi

  local expected_hash actual_hash
  expected_hash="$(sha_file "$desired_file")"
  actual_hash="$(head -n 1 "$state_dir/demo.sha256" | tr -d '[:space:]')"
  if ! assert_eq "$expected_hash" "$actual_hash"; then
    fail "$name" "state hash was not refreshed"
    return
  fi

  pass "$name"
}

test_apply_force_for_drift() {
  local name="apply-force-drift"

  printf 'beta\n' >"$desired_file"
  printf 'gamma\n' >"$actual_file"
  printf '%s\n' "$(sha_file "$desired_file")" >"$state_dir/demo.sha256"

  if run_core apply 0 0; then
    fail "$name" "apply without --force unexpectedly succeeded"
    return
  fi

  if ! grep -Fqx 'gamma' "$actual_file"; then
    fail "$name" "actual changed despite unresolved drift"
    return
  fi

  if ! run_core apply 0 1; then
    fail "$name" "apply with --force failed"
    return
  fi

  if ! diff -u "$desired_file" "$actual_file" >/dev/null 2>&1; then
    fail "$name" "force apply did not align actual with desired"
    return
  fi

  pass "$name"
}

test_adopt_conflict_in_place() {
  local name="adopt-conflict-in-place"
  local base_file

  base_file="$tmp_root/base.txt"
  printf 'base\n' >"$base_file"
  printf '%s\n' "$(sha_file "$base_file")" >"$state_dir/demo.sha256"
  printf 'repo-change\n' >"$desired_file"
  printf 'local-change\n' >"$actual_file"

  if run_core adopt 1 0; then
    fail "$name" "adopt in-place without --force unexpectedly succeeded"
    return
  fi

  if ! grep -Fqx 'repo-change' "$desired_file"; then
    fail "$name" "desired content changed despite refusal"
    return
  fi

  if ! run_core adopt 1 1; then
    fail "$name" "adopt in-place with --force failed"
    return
  fi

  if ! diff -u "$desired_file" "$actual_file" >/dev/null 2>&1; then
    fail "$name" "desired did not adopt actual content"
    return
  fi

  pass "$name"
}

test_forget_state() {
  local name="forget-state"

  if [[ ! -f "$state_dir/demo.sha256" ]]; then
    printf '%s\n' "$(sha_file "$desired_file")" >"$state_dir/demo.sha256"
  fi

  if ! run_core forget 0 0; then
    fail "$name" "forget mode returned non-zero"
    return
  fi

  if [[ -f "$state_dir/demo.sha256" ]]; then
    fail "$name" "state file still exists after forget"
    return
  fi

  pass "$name"
}

test_default_item_selection() {
  local name="default-item-selection"
  local output

  printf 'beta\n' >"$desired_file"
  printf 'beta\n' >"$actual_file"

  if output="$(run_core check 0 0 "missing-item" 2>&1)"; then
    fail "$name" "check unexpectedly succeeded for unmatched --item"
    return
  fi

  if [[ $output != *"no item matched --item 'missing-item'"* ]]; then
    fail "$name" "default no-selection message did not include --item"
    return
  fi

  if ! run_core check 0 0 "demo" >/dev/null 2>&1; then
    fail "$name" "check failed for matching --item"
    return
  fi

  pass "$name"
}

main() {
  printf 'test: running sync-core fake adapter tests\n'
  printf 'test: temp root = %s\n' "$tmp_root"

  test_apply_safe_update
  test_apply_force_for_drift
  test_adopt_conflict_in_place
  test_forget_state
  test_default_item_selection

  printf 'test: summary pass=%s fail=%s\n' "$pass_count" "$fail_count"

  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
