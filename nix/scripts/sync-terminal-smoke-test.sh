#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
TERMINAL_LIB="$ROOT/nix/scripts/sync-adapters/terminal-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/sync-terminal-smoke-test.sh

Description:
  Runs terminal sync smoke checks against a synthetic plist via
  DOTFILES_TERMINAL_SYNC_PLIST, including apply commit behavior.
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
if [[ ! -f $TERMINAL_LIB ]]; then
  echo "test: terminal lib not found: $TERMINAL_LIB" >&2
  exit 1
fi

# shellcheck source=sync-adapters/terminal-lib.sh
source "$TERMINAL_LIB"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/terminal-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

profiles_dir="$tmp_root/profiles"
state_dir="$tmp_root/state"
plist_file="$tmp_root/com.apple.Terminal.plist"
profile_file="$profiles_dir/Smoke.terminal"
profile_name="Smoke Profile"
mkdir -p "$profiles_dir" "$state_dir"

write_terminal_plist() {
  local cursor_type="$1"
  cat >"$plist_file" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Window Settings</key>
  <dict>
    <key>$profile_name</key>
    <dict>
      <key>name</key>
      <string>$profile_name</string>
      <key>CursorType</key>
      <integer>$cursor_type</integer>
      <key>CursorBlink</key>
      <false/>
    </dict>
  </dict>
</dict>
</plist>
EOF_PLIST
}

write_profile_file() {
  local cursor_type="$1"
  cat >"$profile_file" <<EOF_PROFILE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CursorBlink</key>
  <false/>
  <key>CursorType</key>
  <integer>$cursor_type</integer>
  <key>name</key>
  <string>$profile_name</string>
</dict>
</plist>
EOF_PROFILE
}

read_plist_cursor() {
  /usr/libexec/PlistBuddy -c "Print :\"Window Settings\":\"$profile_name\":CursorType" "$plist_file" 2>/dev/null || true
}

read_profile_cursor() {
  /usr/bin/plutil -extract CursorType raw -o - "$profile_file" 2>/dev/null || true
}

read_default_profile_setting() {
  /usr/libexec/PlistBuddy -c 'Print :"Default Window Settings"' "$plist_file" 2>/dev/null || true
}

read_startup_profile_setting() {
  /usr/libexec/PlistBuddy -c 'Print :"Startup Window Settings"' "$plist_file" 2>/dev/null || true
}

desired_hash() {
  local tmp_bin
  tmp_bin="$(mktemp)"
  /usr/bin/plutil -convert binary1 -o "$tmp_bin" "$profile_file" >/dev/null 2>&1
  /usr/bin/shasum -a 256 "$tmp_bin" | /usr/bin/awk '{print $1}'
  rm -f "$tmp_bin"
}

run_terminal_sync() {
  DOTFILES_TERMINAL_SYNC_PLIST="$plist_file" \
    bash "$SYNC_SCRIPT" terminal "$@" \
    --profiles-dir "$profiles_dir" \
    --state-dir "$state_dir"
}

run_terminal_sync_fail_commit() {
  DOTFILES_TERMINAL_SYNC_PLIST="$plist_file" \
    DOTFILES_TERMINAL_SYNC_FAIL_COMMIT=1 \
    bash "$SYNC_SCRIPT" terminal "$@" \
    --profiles-dir "$profiles_dir" \
    --state-dir "$state_dir"
}

printf 'test: running terminal sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

write_terminal_plist 0
write_profile_file 0

if ! run_terminal_sync --check >/dev/null; then
  echo "FAIL: initial check failed" >&2
  exit 1
fi

state_key="$(profile_state_key "$profile_name")"
printf '%s\n' "$(desired_hash)" >"$state_dir/$state_key.sha256"

write_terminal_plist 1
if run_terminal_sync --check >/dev/null; then
  echo "FAIL: check unexpectedly passed with drift" >&2
  exit 1
fi

if ! run_terminal_sync --adopt --in-place --item "$profile_name" >/dev/null; then
  echo "FAIL: adopt in-place failed" >&2
  exit 1
fi

cursor_after_adopt="$(read_profile_cursor)"
if [[ $cursor_after_adopt != "1" ]]; then
  echo "FAIL: adopt did not update desired profile content" >&2
  exit 1
fi

if ! run_terminal_sync --check >/dev/null; then
  echo "FAIL: check failed after adopt" >&2
  exit 1
fi

write_profile_file 2
if ! run_terminal_sync --apply --default-profile "$profile_name" --startup-profile "$profile_name" >/dev/null; then
  echo "FAIL: apply failed for safe update" >&2
  exit 1
fi

cursor_after_apply="$(read_plist_cursor)"
if [[ $cursor_after_apply != "2" ]]; then
  echo "FAIL: apply did not update synthetic plist" >&2
  exit 1
fi

default_after_apply="$(read_default_profile_setting)"
if [[ $default_after_apply != "$profile_name" ]]; then
  echo "FAIL: apply did not set Default Window Settings" >&2
  exit 1
fi

startup_after_apply="$(read_startup_profile_setting)"
if [[ $startup_after_apply != "$profile_name" ]]; then
  echo "FAIL: apply did not set Startup Window Settings" >&2
  exit 1
fi

state_after_apply="$(head -n 1 "$state_dir/$state_key.sha256" | tr -d '[:space:]')"
expected_state_after_apply="$(desired_hash)"
if [[ $state_after_apply != "$expected_state_after_apply" ]]; then
  echo "FAIL: apply did not refresh lastApplied state" >&2
  exit 1
fi

write_profile_file 3
state_before_failed_apply="$state_after_apply"
if run_terminal_sync_fail_commit --apply --default-profile "$profile_name" --startup-profile "$profile_name" >/dev/null; then
  echo "FAIL: apply unexpectedly succeeded when commit hook was forced to fail" >&2
  exit 1
fi

cursor_after_failed_apply="$(read_plist_cursor)"
if [[ $cursor_after_failed_apply != "2" ]]; then
  echo "FAIL: failed apply mutated synthetic plist" >&2
  exit 1
fi

state_after_failed_apply="$(head -n 1 "$state_dir/$state_key.sha256" | tr -d '[:space:]')"
if [[ $state_after_failed_apply != "$state_before_failed_apply" ]]; then
  echo "FAIL: failed apply unexpectedly changed lastApplied state" >&2
  exit 1
fi

echo "PASS: terminal sync smoke"
