#!/usr/bin/env bash
set -euo pipefail

LAUNCHER="${DOTFILES_VSCODE_ZSH_LAUNCHER:-dotfiles-vscode-zsh}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vscode-zsh-launcher.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

HOME_DIR="$TMP_ROOT/home"
FAKE_ZSH="$TMP_ROOT/fake-zsh"
LOG_FILE="$TMP_ROOT/fake-zsh.env"
mkdir -p "$HOME_DIR/.nix"
touch "$HOME_DIR/.nix/.zshrc"

cat >"$FAKE_ZSH" <<EOF_FAKE_ZSH
#!$BASH
set -euo pipefail
{
  printf 'args='
  printf '<%s>' "\$@"
  printf '\n'
  printf 'ZDOTDIR=%s\n' "\${ZDOTDIR-}"
  printf 'USER_ZDOTDIR=%s\n' "\${USER_ZDOTDIR-}"
  printf 'DOTFILES_LAUNCHER_TEST_VAR=%s\n' "\${DOTFILES_LAUNCHER_TEST_VAR-}"
  printf 'PATH=%s\n' "\${PATH-}"
} >"\${DOTFILES_LAUNCHER_LOG:?}"
EOF_FAKE_ZSH
chmod +x "$FAKE_ZSH"

fail() {
  echo "FAIL: $*" >&2
  if [[ -f $LOG_FILE ]]; then
    cat "$LOG_FILE" >&2
  fi
  exit 1
}

assert_line() {
  local expected="$1"

  if ! grep -Fqx -- "$expected" "$LOG_FILE"; then
    fail "missing launcher output line: $expected"
  fi
}

assert_path_starts_with() {
  local expected_prefix="$1"
  local actual_path

  actual_path="$(grep -F 'PATH=' "$LOG_FILE")"
  actual_path="${actual_path#PATH=}"
  case "$actual_path" in
  "$expected_prefix"*) ;;
  *) fail "PATH does not start with $expected_prefix" ;;
  esac
}

run_launcher() {
  local -a extra_env=()

  while [[ $# -gt 0 && $1 == *=* ]]; do
    extra_env+=("$1")
    shift
  done

  : >"$LOG_FILE"
  if [[ ${#extra_env[@]} -gt 0 ]]; then
    env -i \
      HOME="$HOME_DIR" \
      USER=tester \
      LOGNAME=tester \
      PATH="/usr/bin:/bin" \
      DOTFILES_LAUNCHER_LOG="$LOG_FILE" \
      DOTFILES_VSCODE_ZSH_BIN="$FAKE_ZSH" \
      "${extra_env[@]}" \
      "$LAUNCHER" "$@"
  else
    env -i \
      HOME="$HOME_DIR" \
      USER=tester \
      LOGNAME=tester \
      PATH="/usr/bin:/bin" \
      DOTFILES_LAUNCHER_LOG="$LOG_FILE" \
      DOTFILES_VSCODE_ZSH_BIN="$FAKE_ZSH" \
      "$LAUNCHER" "$@"
  fi
}

VSCODE_ZDOTDIR="$TMP_ROOT/vscode-zdotdir"
mkdir -p "$VSCODE_ZDOTDIR"
run_launcher \
  TERM_PROGRAM=vscode \
  VSCODE_INJECTION=1 \
  ZDOTDIR="$VSCODE_ZDOTDIR" \
  USER_ZDOTDIR="$HOME_DIR/.nix" \
  -l
assert_line "args=<-l>"
assert_line "ZDOTDIR=$VSCODE_ZDOTDIR"
assert_line "USER_ZDOTDIR=$HOME_DIR/.nix"

run_launcher -i
assert_line "args=<-i>"
assert_line "ZDOTDIR=$HOME_DIR/.nix"

PROFILE_DIR="$TMP_ROOT/profile"
mkdir -p "$PROFILE_DIR/bin" "$PROFILE_DIR/etc/profile.d"
cat >"$PROFILE_DIR/etc/profile.d/hm-session-vars.sh" <<'EOF_HM_SESSION_VARS'
if [ -n "$__HM_SESS_VARS_SOURCED" ]; then return; fi
export __HM_SESS_VARS_SOURCED=1
export DOTFILES_LAUNCHER_TEST_VAR=from_hm_session_vars
EOF_HM_SESSION_VARS

run_launcher DOTFILES_PROFILE_DIRS="$PROFILE_DIR" -l
assert_line "DOTFILES_LAUNCHER_TEST_VAR=from_hm_session_vars"
assert_path_starts_with "$PROFILE_DIR/bin:"

if [[ $(uname -s) == Darwin ]]; then
  assert_darwin_system_zsh() {
    local label="$1"
    shift
    local selected

    selected="$(
      env -i \
        HOME="$HOME_DIR" \
        USER=tester \
        LOGNAME=tester \
        PATH="/usr/bin:/bin" \
        "$@" \
        "$LAUNCHER" -dfc 'print -r -- "$ZSH_ARGZERO"'
    )"

    if [[ $selected != /bin/zsh ]]; then
      fail "$label selected $selected instead of /bin/zsh"
    fi
  }

  assert_darwin_system_zsh "VS Code" TERM_PROGRAM=vscode
  assert_darwin_system_zsh "Cursor" TERM_PROGRAM=cursor
  assert_darwin_system_zsh "Kiro" TERM_PROGRAM=kiro
  assert_darwin_system_zsh "injected VS Code family" VSCODE_INJECTION=1
  assert_darwin_system_zsh "active shell integration" VSCODE_SHELL_INTEGRATION=1
fi

echo "PASS: vscode zsh launcher"
