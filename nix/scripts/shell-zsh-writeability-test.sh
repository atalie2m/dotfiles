#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHELL_SYNC_SCRIPT="$ROOT/nix/scripts/shell.sh"
MANAGED_DIR="$ROOT/apps/shell/managed"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/shell-zsh-writeability-test.sh

Description:
  Runs isolated integration tests for zsh shell sync behavior.
  Uses temporary HOME/XDG_STATE_HOME and removes all test files on exit.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x $SHELL_SYNC_SCRIPT ]]; then
  echo "test: shell sync script not executable: $SHELL_SYNC_SCRIPT" >&2
  exit 1
fi

if [[ ! -d $MANAGED_DIR ]]; then
  echo "test: managed dir not found: $MANAGED_DIR" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shell-zsh-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

pass_count=0
fail_count=0

pass() {
  local name="$1"
  echo "PASS: $name"
  pass_count=$((pass_count + 1))
}

fail() {
  local name="$1"
  local message="$2"
  echo "FAIL: $name - $message" >&2
  fail_count=$((fail_count + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    return 1
  fi
  return 0
}

run_shell_sync() {
  local home_dir="$1"
  local state_dir="$2"
  shift 2

  HOME="$home_dir" \
    XDG_STATE_HOME="$state_dir" \
    "$SHELL_SYNC_SCRIPT" sync "$@" \
      --managed-dir "$MANAGED_DIR" \
      --state-dir "$state_dir/blocks"
}

new_test_env() {
  local name="$1"
  local home_dir="$tmp_root/$name/home"
  local state_dir="$tmp_root/$name/state"
  mkdir -p "$home_dir" "$state_dir"
  printf '%s|%s\n' "$home_dir" "$state_dir"
}

test_fresh_apply_creates_writable_wrapper_and_link() {
  local name="fresh-apply"
  local env_data home_dir state_dir link_target first_line
  env_data="$(new_test_env "$name")"
  home_dir="${env_data%%|*}"
  state_dir="${env_data##*|}"

  if ! run_shell_sync "$home_dir" "$state_dir" --apply --shell zsh >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if [[ ! -f "$home_dir/.nix/.zshrc" ]]; then
    fail "$name" "wrapper file missing: $home_dir/.nix/.zshrc"
    return
  fi

  if [[ ! -L "$home_dir/.zshrc" ]]; then
    fail "$name" "~/.zshrc is not a symlink"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if ! assert_eq ".nix/.zshrc" "$link_target"; then
    fail "$name" "unexpected compat link target: $link_target"
    return
  fi

  first_line="$(head -n 1 "$home_dir/.nix/.zshrc" || true)"
  if ! assert_eq "# >>> dotfiles-managed:zdotdir.zshrc >>>" "$first_line"; then
    fail "$name" "managed block marker missing at top of wrapper"
    return
  fi

  if ! run_shell_sync "$home_dir" "$state_dir" --check --shell zsh >/dev/null; then
    fail "$name" "post-apply check failed"
    return
  fi

  pass "$name"
}

test_existing_mutable_wrapper_preserves_installer_tail() {
  local name="mutable-wrapper-preserve-tail"
  local env_data home_dir state_dir wrapper_file first_line end_line installer_line
  env_data="$(new_test_env "$name")"
  home_dir="${env_data%%|*}"
  state_dir="${env_data##*|}"
  wrapper_file="$home_dir/.nix/.zshrc"

  mkdir -p "$home_dir/.nix"
  cat >"$wrapper_file" <<'EOF'
export SDKMAN_DIR="$HOME/.sdkman"
# installer line
EOF

  if ! run_shell_sync "$home_dir" "$state_dir" --apply --target zsh-zdotdir >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  first_line="$(head -n 1 "$wrapper_file" || true)"
  if ! assert_eq "# >>> dotfiles-managed:zdotdir.zshrc >>>" "$first_line"; then
    fail "$name" "managed block marker missing at top"
    return
  fi

  if ! grep -Fqx 'export SDKMAN_DIR="$HOME/.sdkman"' "$wrapper_file"; then
    fail "$name" "installer line was not preserved"
    return
  fi

  end_line="$(grep -n '^# <<< dotfiles-managed:zdotdir.zshrc <<<$' "$wrapper_file" | head -n 1 | cut -d: -f1 || true)"
  installer_line="$(grep -n '^export SDKMAN_DIR="\$HOME/.sdkman"$' "$wrapper_file" | head -n 1 | cut -d: -f1 || true)"
  if [[ -z "$end_line" || -z "$installer_line" || "$installer_line" -le "$end_line" ]]; then
    fail "$name" "installer lines are not in unmanaged tail"
    return
  fi

  pass "$name"
}

test_legacy_store_symlink_is_replaced_with_regular_file() {
  local name="store-symlink-migration"
  local env_data home_dir state_dir wrapper_file
  env_data="$(new_test_env "$name")"
  home_dir="${env_data%%|*}"
  state_dir="${env_data##*|}"
  wrapper_file="$home_dir/.nix/.zshrc"

  mkdir -p "$home_dir/.nix"
  ln -s "/nix/store/fake-legacy-zshrc" "$wrapper_file"

  if ! run_shell_sync "$home_dir" "$state_dir" --apply --target zsh-zdotdir >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if [[ -L "$wrapper_file" ]]; then
    fail "$name" "wrapper is still a symlink"
    return
  fi

  if [[ ! -f "$wrapper_file" ]]; then
    fail "$name" "wrapper regular file missing after migration"
    return
  fi

  if ! grep -Fqx '# >>> dotfiles-managed:zdotdir.zshrc >>>' "$wrapper_file"; then
    fail "$name" "managed block marker missing after migration"
    return
  fi

  pass "$name"
}

test_compat_link_legacy_to_new_target() {
  local name="compat-link-migration"
  local env_data home_dir state_dir link_target
  env_data="$(new_test_env "$name")"
  home_dir="${env_data%%|*}"
  state_dir="${env_data##*|}"

  mkdir -p "$home_dir"
  cat >"$home_dir/.zshrc.local" <<'EOF'
# local
EOF
  ln -s ".zshrc.local" "$home_dir/.zshrc"

  if ! run_shell_sync "$home_dir" "$state_dir" --apply --target zsh-zdotdir >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if [[ ! -L "$home_dir/.zshrc" ]]; then
    fail "$name" "~/.zshrc is not a symlink after apply"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if ! assert_eq ".nix/.zshrc" "$link_target"; then
    fail "$name" "compat symlink was not migrated: $link_target"
    return
  fi

  pass "$name"
}

test_fallback_link_when_wrapper_not_selected() {
  local name="fallback-link-zsh-local-only"
  local env_data home_dir state_dir link_target
  env_data="$(new_test_env "$name")"
  home_dir="${env_data%%|*}"
  state_dir="${env_data##*|}"

  if ! run_shell_sync "$home_dir" "$state_dir" --apply --target zsh-local >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if [[ ! -L "$home_dir/.zshrc" ]]; then
    fail "$name" "~/.zshrc is not a symlink"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if ! assert_eq ".zshrc.local" "$link_target"; then
    fail "$name" "unexpected fallback link target: $link_target"
    return
  fi

  pass "$name"
}

main() {
  echo "test: running zsh writeability integration tests"
  echo "test: temp root = $tmp_root"

  test_fresh_apply_creates_writable_wrapper_and_link
  test_existing_mutable_wrapper_preserves_installer_tail
  test_legacy_store_symlink_is_replaced_with_regular_file
  test_compat_link_legacy_to_new_target
  test_fallback_link_when_wrapper_not_selected

  echo "test: summary pass=$pass_count fail=$fail_count"

  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
