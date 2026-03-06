#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPAT_SCRIPT="$ROOT/nix/scripts/zshrc-compat.sh"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
MANAGED_DIR="$ROOT/surfaces/shell/desired"
MIGRATION_MARKER="# migrated from ~/.zshrc by zshrc-compat"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/zshrc-compat-test.sh

Description:
  Runs isolated tests for the ~/.zshrc compat helper.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f $COMPAT_SCRIPT ]]; then
  echo "test: compat script not found: $COMPAT_SCRIPT" >&2
  exit 1
fi
if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi
if [[ ! -d $MANAGED_DIR ]]; then
  echo "test: managed dir not found: $MANAGED_DIR" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/zshrc-compat-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

pass_count=0
fail_count=0

pass() {
  echo "PASS: $1"
  pass_count=$((pass_count + 1))
}

fail() {
  echo "FAIL: $1 - $2" >&2
  fail_count=$((fail_count + 1))
}

run_compat() {
  local home_dir="$1"
  shift
  HOME="$home_dir" bash "$COMPAT_SCRIPT" "$@"
}

run_shell_sync() {
  local home_dir="$1"
  shift
  HOME="$home_dir" bash "$SYNC_SCRIPT" shell "$@" --managed-dir "$MANAGED_DIR"
}

new_test_home() {
  local name="$1"
  local home_dir="$tmp_root/$name/home"
  mkdir -p "$home_dir"
  printf '%s\n' "$home_dir"
}

test_missing_apply_creates_symlink() {
  local name="missing-apply-creates-symlink"
  local home_dir link_target

  home_dir="$(new_test_home "$name")"

  if ! run_compat "$home_dir" --apply >/dev/null; then
    fail "$name" "apply failed"
    return
  fi

  if [[ ! -L "$home_dir/.zshrc" ]]; then
    fail "$name" "$home_dir/.zshrc is not a symlink"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if [[ $link_target != ".nix/.zshrc" ]]; then
    fail "$name" "unexpected symlink target: $link_target"
    return
  fi

  if [[ ! -f "$home_dir/.nix/.zshrc" || -L "$home_dir/.nix/.zshrc" ]]; then
    fail "$name" "runtime wrapper was not prepared as a regular file"
    return
  fi

  pass "$name"
}

test_correct_symlink_is_noop() {
  local name="correct-symlink-is-noop"
  local home_dir link_target

  home_dir="$(new_test_home "$name")"
  if ! run_compat "$home_dir" --apply >/dev/null; then
    fail "$name" "initial apply failed"
    return
  fi

  if ! run_compat "$home_dir" --check >/dev/null; then
    fail "$name" "check failed for correct symlink"
    return
  fi

  if ! run_compat "$home_dir" --apply >/dev/null; then
    fail "$name" "second apply failed"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if [[ $link_target != ".nix/.zshrc" ]]; then
    fail "$name" "symlink target changed: $link_target"
    return
  fi

  pass "$name"
}

test_regular_file_check_and_apply_refuse() {
  local name="regular-file-refuses-apply"
  local home_dir err_file

  home_dir="$(new_test_home "$name")"
  cat >"$home_dir/.zshrc" <<'EOF_ZSHRC'
export PATH="$HOME/.local/bin:$PATH"
EOF_ZSHRC
  err_file="$tmp_root/$name.err"

  if run_compat "$home_dir" --check >"$tmp_root/$name.out" 2>"$err_file"; then
    fail "$name" "check unexpectedly succeeded"
    return
  fi

  if run_compat "$home_dir" --apply >"$tmp_root/$name.apply.out" 2>"$err_file"; then
    fail "$name" "apply unexpectedly succeeded"
    return
  fi

  if ! grep -Fq "apply refused" "$err_file"; then
    fail "$name" "apply refusal message missing"
    return
  fi

  pass "$name"
}

test_regular_file_migrate_creates_backup_and_symlink() {
  local name="regular-file-migrate"
  local home_dir backup_file link_target

  home_dir="$(new_test_home "$name")"
  cat >"$home_dir/.zshrc" <<'EOF_ZSHRC'
export PATH="$HOME/.local/bin:$PATH"
# local zshrc content
EOF_ZSHRC

  if ! run_compat "$home_dir" --migrate >/dev/null; then
    fail "$name" "migrate failed"
    return
  fi

  backup_file="$(find "$home_dir" -maxdepth 1 -type f -name '.zshrc.pre-dotfiles-compat.*.bak' | head -n 1)"
  if [[ -z $backup_file || ! -f $backup_file ]]; then
    fail "$name" "backup file was not created"
    return
  fi

  if [[ ! -L "$home_dir/.zshrc" ]]; then
    fail "$name" "$home_dir/.zshrc is not a symlink after migrate"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if [[ $link_target != ".nix/.zshrc" ]]; then
    fail "$name" "unexpected symlink target after migrate: $link_target"
    return
  fi

  if ! grep -Fqx "$MIGRATION_MARKER" "$home_dir/.nix/.zshrc"; then
    fail "$name" "migration marker missing from runtime wrapper"
    return
  fi

  if ! grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$home_dir/.nix/.zshrc"; then
    fail "$name" "migrated content missing from runtime wrapper"
    return
  fi

  if ! run_shell_sync "$home_dir" --apply --item zsh-zdotdir >/dev/null; then
    fail "$name" "shell sync apply failed after migrate"
    return
  fi

  if ! grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$home_dir/.nix/.zshrc"; then
    fail "$name" "shell sync apply did not preserve migrated unmanaged tail"
    return
  fi

  pass "$name"
}

test_different_symlink_refuses() {
  local name="different-symlink-refuses"
  local home_dir err_file

  home_dir="$(new_test_home "$name")"
  cat >"$home_dir/.zshrc.local" <<'EOF_LOCAL'
# local
EOF_LOCAL
  ln -s ".zshrc.local" "$home_dir/.zshrc"
  err_file="$tmp_root/$name.err"

  if run_compat "$home_dir" --check >"$tmp_root/$name.out" 2>"$err_file"; then
    fail "$name" "check unexpectedly succeeded"
    return
  fi

  if run_compat "$home_dir" --apply >"$tmp_root/$name.apply.out" 2>"$err_file"; then
    fail "$name" "apply unexpectedly succeeded"
    return
  fi

  if ! grep -Fq "status=conflict" "$err_file"; then
    fail "$name" "conflict status missing"
    return
  fi

  pass "$name"
}

test_directory_refuses() {
  local name="directory-refuses"
  local home_dir err_file

  home_dir="$(new_test_home "$name")"
  mkdir -p "$home_dir/.zshrc"
  err_file="$tmp_root/$name.err"

  if run_compat "$home_dir" --check >"$tmp_root/$name.out" 2>"$err_file"; then
    fail "$name" "check unexpectedly succeeded"
    return
  fi

  if run_compat "$home_dir" --apply >"$tmp_root/$name.apply.out" 2>"$err_file"; then
    fail "$name" "apply unexpectedly succeeded"
    return
  fi

  if ! grep -Fq "detail=directory" "$err_file"; then
    fail "$name" "directory conflict detail missing"
    return
  fi

  pass "$name"
}

main() {
  echo "test: running zshrc compat tests"
  echo "test: temp root = $tmp_root"

  test_missing_apply_creates_symlink
  test_correct_symlink_is_noop
  test_regular_file_check_and_apply_refuse
  test_regular_file_migrate_creates_backup_and_symlink
  test_different_symlink_refuses
  test_directory_refuses

  echo "test: summary pass=$pass_count fail=$fail_count"
  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
