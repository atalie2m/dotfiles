#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/shim-delegation.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

FAKE_DOTFILES="$TMP_ROOT/fake-dotfiles"
LOG_FILE="$TMP_ROOT/delegation.log"
PROFILE_HOME="$TMP_ROOT/profile-home"
PROFILE_DOTFILES="$PROFILE_HOME/.nix-profile/bin/dotfiles"

cat >"$FAKE_DOTFILES" <<EOF_FAKE
#!$BASH
set -euo pipefail
printf '%s\n' "\$*" >>"\${FAKE_DOTFILES_LOG_FILE:?}"
EOF_FAKE
chmod +x "$FAKE_DOTFILES"

mkdir -p "$(dirname "$PROFILE_DOTFILES")"
cat >"$PROFILE_DOTFILES" <<'EOF_PROFILE'
#!/usr/bin/env bash
set -euo pipefail
printf 'profile %s\n' "$*" >>"${FAKE_DOTFILES_LOG_FILE:?}"
EOF_PROFILE
chmod +x "$PROFILE_DOTFILES"

run_wrapper() {
  local script="$1"
  shift
  FAKE_DOTFILES_LOG_FILE="$LOG_FILE" \
    DOTFILES_BIN="$FAKE_DOTFILES" \
    "$BASH" "$script" "$@" >/dev/null
}

assert_logged() {
  local expected="$1"
  if ! grep -Fqx -- "$expected" "$LOG_FILE"; then
    echo "FAIL: wrapper delegation changed: $expected" >&2
    cat "$LOG_FILE" >&2 || true
    exit 1
  fi
}

assert_logged_count() {
  local expected="$1"
  local count="$2"
  local actual
  actual=$(grep -Fxc -- "$expected" "$LOG_FILE")
  if [[ $actual != "$count" ]]; then
    echo "FAIL: wrapper delegation count changed: $expected ($actual != $count)" >&2
    cat "$LOG_FILE" >&2 || true
    exit 1
  fi
}

run_wrapper "$ROOT/scripts/apply.sh" --host own_mac --action build
run_wrapper "$ROOT/scripts/update.sh" --host own_mac
run_wrapper "$ROOT/scripts/list-tools.sh" --host own_mac --format json
run_wrapper "$ROOT/scripts/doctor.sh" --json
run_wrapper "$ROOT/scripts/bootstrap.sh" --host own_mac --apply
run_wrapper "$ROOT/scripts/export-clean.sh" --format dir --output "$TMP_ROOT/export"
run_wrapper "$ROOT/scripts/gc.sh" --apply
run_wrapper "$ROOT/scripts/matrix-tools.sh" --full --format json
run_wrapper "$ROOT/scripts/sync.sh" shell --check
run_wrapper "$ROOT/scripts/sync.sh" emacs --check
run_wrapper "$ROOT/scripts/sync.sh" neovim --check
run_wrapper "$ROOT/scripts/dotfiles.sh" sync vscode --check --profile native
run_wrapper "$ROOT/scripts/codex-slack-notification" --dry-run
run_wrapper "$ROOT/scripts/agent-notifications-update" --no-install
run_wrapper "$ROOT/scripts/codex-slack-update" --no-install
FAKE_DOTFILES_LOG_FILE="$LOG_FILE" HOME="$PROFILE_HOME" PATH="/usr/bin:/bin" \
  bash "$ROOT/scripts/codex-slack-notification" --dry-run >/dev/null

assert_logged "apply --host own_mac --action build"
assert_logged "update --host own_mac"
assert_logged "list-tools --host own_mac --format json"
assert_logged "doctor --json"
assert_logged "bootstrap --host own_mac --apply"
assert_logged "export-clean --format dir --output $TMP_ROOT/export"
assert_logged "gc --apply"
assert_logged "matrix-tools --full --format json"
assert_logged "sync shell --check"
assert_logged "sync emacs --check"
assert_logged "sync neovim --check"
assert_logged "sync vscode --check --profile native"
assert_logged "agent-notify codex --dry-run"
assert_logged_count "agent-notify update-runtime --no-install" 2
assert_logged "profile agent-notify codex --dry-run"

echo "PASS: shim delegation"
