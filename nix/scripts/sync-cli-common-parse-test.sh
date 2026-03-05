#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
SOURCE_MANAGED_DIR="$ROOT/surfaces/shell/desired"
TERMINAL_LIB="$ROOT/nix/scripts/sync-adapters/terminal-lib.sh"

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

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-cli-common.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

shell_home="$tmp_root/shell-home"
shell_managed="$tmp_root/shell-managed"
shell_state="$tmp_root/shell-state"
terminal_profiles="$tmp_root/terminal-profiles"
terminal_state="$tmp_root/terminal-state"
terminal_plist="$tmp_root/com.apple.Terminal.plist"
profile_name="Parse Profile"
profile_file="$terminal_profiles/ParseProfile.terminal"

mkdir -p "$shell_home" "$shell_state" "$terminal_profiles" "$terminal_state"
cp -R "$SOURCE_MANAGED_DIR" "$shell_managed"
chmod -R u+w "$shell_managed"

cat >"$profile_file" <<EOF_PROFILE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CursorBlink</key>
  <false/>
  <key>CursorType</key>
  <integer>0</integer>
  <key>name</key>
  <string>$profile_name</string>
</dict>
</plist>
EOF_PROFILE

cat >"$terminal_plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Window Settings</key>
  <dict>
    <key>$profile_name</key>
    <dict>
      <key>CursorBlink</key>
      <false/>
      <key>CursorType</key>
      <integer>0</integer>
      <key>name</key>
      <string>$profile_name</string>
    </dict>
  </dict>
</dict>
</plist>
EOF_PLIST

run_shell_sync() {
  HOME="$shell_home" \
    XDG_STATE_HOME="$tmp_root/xdg-state" \
    bash "$SYNC_SCRIPT" shell "$@" \
    --managed-dir "$shell_managed" \
    --state-dir "$shell_state"
}

run_terminal_sync() {
  DOTFILES_TERMINAL_SYNC_PLIST="$terminal_plist" \
    bash "$SYNC_SCRIPT" terminal "$@" \
    --profiles-dir "$terminal_profiles" \
    --state-dir "$terminal_state"
}

printf 'test: running sync cli common parse test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_shell_sync --migrate --item bash-rc >/dev/null; then
  echo "FAIL: shell migrate failed" >&2
  exit 1
fi
if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: shell apply failed" >&2
  exit 1
fi
if [[ ! -f "$shell_state/bash-rc.sha256" ]]; then
  echo "FAIL: shell --state-dir did not receive state file" >&2
  exit 1
fi
if ! run_shell_sync --forget --item bash-rc >/dev/null; then
  echo "FAIL: shell forget failed" >&2
  exit 1
fi
if [[ -f "$shell_state/bash-rc.sha256" ]]; then
  echo "FAIL: shell forget did not remove state in --state-dir" >&2
  exit 1
fi

terminal_state_key="$(profile_state_key "$profile_name")"
printf 'deadbeef\n' >"$terminal_state/$terminal_state_key.sha256"
if ! run_terminal_sync --forget --item "$profile_name" >/dev/null; then
  echo "FAIL: terminal forget failed" >&2
  exit 1
fi
if [[ -f "$terminal_state/$terminal_state_key.sha256" ]]; then
  echo "FAIL: terminal forget did not remove state in --state-dir" >&2
  exit 1
fi

missing_item="missing-parse-item"
if run_shell_sync --check --item "$missing_item" >/dev/null 2>"$tmp_root/shell.err"; then
  echo "FAIL: shell check unexpectedly passed for missing --item" >&2
  exit 1
fi
if ! grep -Fq "no item matched --item '$missing_item'" "$tmp_root/shell.err"; then
  echo "FAIL: shell missing-item message did not use common wording" >&2
  exit 1
fi

if run_terminal_sync --check --item "$missing_item" >/dev/null 2>"$tmp_root/terminal.err"; then
  echo "FAIL: terminal check unexpectedly passed for missing --item" >&2
  exit 1
fi
if ! grep -Fq "no item matched --item '$missing_item'" "$tmp_root/terminal.err"; then
  echo "FAIL: terminal missing-item message did not use common wording" >&2
  exit 1
fi

echo "PASS: sync cli common parse"
