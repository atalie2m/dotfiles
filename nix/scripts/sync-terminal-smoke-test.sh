#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERMINAL_SYNC_SCRIPT="$ROOT/nix/scripts/terminal.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/sync-terminal-smoke-test.sh

Description:
  Runs a lightweight terminal sync smoke test using a synthetic Terminal plist
  via DOTFILES_TERMINAL_SYNC_PLIST.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x $TERMINAL_SYNC_SCRIPT ]]; then
  echo "test: terminal sync script not executable: $TERMINAL_SYNC_SCRIPT" >&2
  exit 1
fi

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

export_profile_from_plist() {
  local tmp_xml
  tmp_xml="$(mktemp)"
  /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$profile_name\"" "$plist_file" >"$tmp_xml" 2>/dev/null
  /usr/bin/plutil -convert xml1 -o "$profile_file" "$tmp_xml" >/dev/null 2>&1
  rm -f "$tmp_xml"
}

profile_state_key() {
  local name="$1"
  local short_hash prefix

  short_hash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1, 1, 12)}')"
  prefix="$(printf '%s' "$name" | /usr/bin/tr '[:space:]' '-' | /usr/bin/tr -cd '[:alnum:]._-')"
  [[ -z $prefix ]] && prefix="profile"
  printf '%s.%s\n' "$prefix" "$short_hash"
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
    "$TERMINAL_SYNC_SCRIPT" sync "$@" \
      --dir "$profiles_dir" \
      --state-dir "$state_dir"
}

printf 'test: running terminal sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

write_terminal_plist 0
export_profile_from_plist

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

if ! run_terminal_sync --adopt --in-place --profile "$profile_name" >/dev/null; then
  echo "FAIL: adopt in-place failed" >&2
  exit 1
fi

cursor_after="$(/usr/bin/plutil -extract CursorType raw "$profile_file" 2>/dev/null || true)"
if [[ "$cursor_after" != "1" ]]; then
  echo "FAIL: adopted profile file did not match Terminal current value" >&2
  exit 1
fi

if ! run_terminal_sync --check >/dev/null; then
  echo "FAIL: final check failed after adopt" >&2
  exit 1
fi

echo "PASS: terminal sync smoke"
