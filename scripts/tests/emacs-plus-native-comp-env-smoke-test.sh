#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFRESH_SCRIPT="$ROOT/nix/modules/tools/editor/refresh-emacs-plus-native-comp-env.sh"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/emacs-plus-native-comp-env-smoke-test.sh

Description:
  Verifies the Emacs+ native compilation environment repair helper.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f $REFRESH_SCRIPT ]]; then
  echo "test: refresh script not found: $REFRESH_SCRIPT" >&2
  exit 1
fi

if [[ ! -x $PLISTBUDDY ]]; then
  echo "test: PlistBuddy not found: $PLISTBUDDY" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/emacs-plus-native-comp-env.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

brew_prefix="$tmp_root/homebrew"
app="$tmp_root/Applications/Emacs.app"
plist="$app/Contents/Info.plist"
machine="aarch64-apple-darwin25"
major="15"
stable_emutls_dir="$brew_prefix/opt/gcc/lib/gcc/current/gcc/$machine/$major"
expected_cc="$brew_prefix/opt/gcc/bin/gcc-$major"
expected_library_path="$stable_emutls_dir:$brew_prefix/lib/gcc/current:$brew_prefix/lib"

mkdir -p \
  "$brew_prefix/bin" \
  "$brew_prefix/opt/gcc/bin" \
  "$stable_emutls_dir" \
  "$brew_prefix/lib/gcc/current" \
  "$brew_prefix/lib" \
  "$app/Contents"

touch "$stable_emutls_dir/libemutls_w.a"

cat >"$brew_prefix/bin/brew" <<'EOF_BREW'
#!/usr/bin/env bash
exit 0
EOF_BREW
chmod +x "$brew_prefix/bin/brew"

cat >"$expected_cc" <<EOF_GCC
#!/usr/bin/env bash
case "\${1:-}" in
  -dumpmachine)
    printf '%s\n' "$machine"
    ;;
  -print-file-name=libemutls_w.a)
    printf '%s\n' "$brew_prefix/Cellar/gcc/15.2.0_1/lib/gcc/current/gcc/$machine/$major/libemutls_w.a"
    ;;
esac
EOF_GCC
chmod +x "$expected_cc"
ln -s "../opt/gcc/bin/gcc-$major" "$brew_prefix/bin/gcc-$major"

write_plist_with_stale_environment() {
  cat >"$plist" <<'EOF_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>org.gnu.Emacs</string>
  <key>LSEnvironment</key>
  <dict>
    <key>CC</key>
    <string>/opt/homebrew/bin/gcc-15</string>
    <key>LIBRARY_PATH</key>
    <string>/opt/homebrew/Cellar/gcc/15.2.0/lib/gcc/current/gcc/aarch64-apple-darwin25/15:/opt/homebrew/lib/gcc/current:/opt/homebrew/lib</string>
  </dict>
</dict>
</plist>
EOF_PLIST
}

plist_value() {
  local key="$1"
  "$PLISTBUDDY" -c "Print :LSEnvironment:$key" "$plist"
}

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plist_value "$key")"
  if [[ $actual != "$expected" ]]; then
    echo "FAIL: unexpected $key" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

run_refresh() {
  HOMEBREW_PREFIX="$brew_prefix" \
    EMACS_PLUS_APP="$app" \
    EMACS_PLUS_SKIP_CODESIGN=1 \
    PLISTBUDDY="$PLISTBUDDY" \
    bash "$REFRESH_SCRIPT"
}

printf 'test: running Emacs+ native comp env smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

write_plist_with_stale_environment
run_refresh
assert_plist_value CC "$expected_cc"
assert_plist_value LIBRARY_PATH "$expected_library_path"

if [[ $(plist_value LIBRARY_PATH) == *"/Cellar/gcc/15.2.0/"* ]]; then
  echo "FAIL: stale Cellar path survived repair" >&2
  exit 1
fi

cat >"$plist" <<'EOF_EMPTY_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>org.gnu.Emacs</string>
</dict>
</plist>
EOF_EMPTY_PLIST

run_refresh
assert_plist_value CC "$expected_cc"
assert_plist_value LIBRARY_PATH "$expected_library_path"

echo "PASS: Emacs+ native comp env smoke"
