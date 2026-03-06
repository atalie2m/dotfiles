#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
MANAGED_DIR="$ROOT/surfaces/shell/desired"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/shell-zsh-writeability-test.sh

Description:
  Runs isolated integration tests for shell entrypoint writeability.
  Uses temporary HOME and removes all test files on exit.
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

assert_regular_file() {
  local path="$1"
  [[ -f $path && ! -L $path ]]
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

fresh_apply_case() {
  local name="$1"
  local item_id="$2"
  local target_path="$3"
  local begin_marker="$4"
  local verify_zshrc="$5"
  local home_dir first_line

  home_dir="$(new_test_home "$name")"

  if ! run_shell_sync "$home_dir" --apply --item "$item_id" >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if ! assert_regular_file "$target_path"; then
    fail "$name" "target is not a writable regular file: $target_path"
    return
  fi

  first_line="$(head -n 1 "$target_path" || true)"
  if [[ $first_line != "$begin_marker" ]]; then
    fail "$name" "managed block marker missing at top"
    return
  fi

  if [[ $verify_zshrc == "yes" && (-e "$home_dir/.zshrc" || -L "$home_dir/.zshrc") ]]; then
    fail "$name" "unexpected side effect: $home_dir/.zshrc was modified"
    return
  fi

  if ! run_shell_sync "$home_dir" --check --item "$item_id" >/dev/null; then
    fail "$name" "post-apply check failed"
    return
  fi

  pass "$name"
}

preserve_tail_case() {
  local name="$1"
  local item_id="$2"
  local target_path="$3"
  local end_marker="$4"
  local seed_content="$5"
  local expected_line="$6"
  local home_dir end_line tail_line

  home_dir="$(new_test_home "$name")"
  mkdir -p "$(dirname "$target_path")"
  cat >"$target_path" <<<"$seed_content"

  if ! run_shell_sync "$home_dir" --apply --item "$item_id" >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if ! grep -Fqx "$expected_line" "$target_path"; then
    fail "$name" "unmanaged line was not preserved"
    return
  fi

  end_line="$(grep -Fxn "$end_marker" "$target_path" | head -n 1 | cut -d: -f1 || true)"
  tail_line="$(grep -n -F "$expected_line" "$target_path" | head -n 1 | cut -d: -f1 || true)"
  if [[ -z $end_line || -z $tail_line || $tail_line -le $end_line ]]; then
    fail "$name" "unmanaged content was not preserved after the managed block"
    return
  fi

  pass "$name"
}

store_symlink_case() {
  local name="$1"
  local item_id="$2"
  local target_path="$3"
  local begin_marker="$4"
  local fake_target="$5"
  local home_dir first_line

  home_dir="$(new_test_home "$name")"
  mkdir -p "$(dirname "$target_path")"
  ln -s "$fake_target" "$target_path"

  if ! run_shell_sync "$home_dir" --apply --item "$item_id" >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if ! assert_regular_file "$target_path"; then
    fail "$name" "target is still not a regular file"
    return
  fi

  first_line="$(head -n 1 "$target_path" || true)"
  if [[ $first_line != "$begin_marker" ]]; then
    fail "$name" "managed block marker missing after repair"
    return
  fi

  if ! run_shell_sync "$home_dir" --check --item "$item_id" >/dev/null; then
    fail "$name" "post-repair check failed"
    return
  fi

  pass "$name"
}

test_existing_zshrc_link_remains_untouched() {
  local name="preserve-existing-zshrc-link"
  local home_dir link_target

  home_dir="$(new_test_home "$name")"
  cat >"$home_dir/.zshrc.local" <<'EOF_LOCAL'
# local
EOF_LOCAL
  ln -s ".zshrc.local" "$home_dir/.zshrc"

  if ! run_shell_sync "$home_dir" --apply --item zsh-zdotdir >/dev/null; then
    fail "$name" "shell sync apply failed"
    return
  fi

  if [[ ! -L "$home_dir/.zshrc" ]]; then
    fail "$name" "$home_dir/.zshrc symlink was removed"
    return
  fi

  link_target="$(readlink "$home_dir/.zshrc" || true)"
  if [[ $link_target != ".zshrc.local" ]]; then
    fail "$name" "existing symlink target changed unexpectedly: $link_target"
    return
  fi

  pass "$name"
}

test_directory_target_is_rejected() {
  local name="directory-target-is-invalid"
  local home_dir err_file

  home_dir="$(new_test_home "$name")"
  mkdir -p "$home_dir/.nix/.zshrc"
  err_file="$tmp_root/$name.err"

  if run_shell_sync "$home_dir" --apply --item zsh-zdotdir >"$tmp_root/$name.out" 2>"$err_file"; then
    fail "$name" "apply unexpectedly succeeded for directory target"
    return
  fi

  if ! grep -Fq "apply refused for 'zsh-zdotdir': target is not a regular file" "$err_file"; then
    fail "$name" "failure message did not describe the invalid directory target"
    return
  fi

  pass "$name"
}

main() {
  echo "test: running shell entrypoint writeability integration tests"
  echo "test: temp root = $tmp_root"

  fresh_apply_case "fresh-zsh-apply" "zsh-zdotdir" "$tmp_root/fresh-zsh-apply/home/.nix/.zshrc" "# >>> dotfiles-managed:zdotdir.zshrc >>>" "yes"
  preserve_tail_case "zsh-preserve-tail" "zsh-zdotdir" "$tmp_root/zsh-preserve-tail/home/.nix/.zshrc" "# <<< dotfiles-managed:zdotdir.zshrc <<<" $'export SDKMAN_DIR="$HOME/.sdkman"\n# installer line' 'export SDKMAN_DIR="$HOME/.sdkman"'
  store_symlink_case "zsh-store-symlink-repair" "zsh-zdotdir" "$tmp_root/zsh-store-symlink-repair/home/.nix/.zshrc" "# >>> dotfiles-managed:zdotdir.zshrc >>>" "/nix/store/fake-legacy-zshrc"

  fresh_apply_case "fresh-bash-apply" "bash-rc" "$tmp_root/fresh-bash-apply/home/.bashrc" "# >>> dotfiles-managed:bashrc >>>" "no"
  preserve_tail_case "bash-preserve-tail" "bash-rc" "$tmp_root/bash-preserve-tail/home/.bashrc" "# <<< dotfiles-managed:bashrc <<<" $'export PATH="$HOME/.local/bin:$PATH"\n# installer line' 'export PATH="$HOME/.local/bin:$PATH"'
  store_symlink_case "bash-store-symlink-repair" "bash-rc" "$tmp_root/bash-store-symlink-repair/home/.bashrc" "# >>> dotfiles-managed:bashrc >>>" "/nix/store/fake-hm-bashrc"

  fresh_apply_case "fresh-fish-apply" "fish-config" "$tmp_root/fresh-fish-apply/home/.config/fish/config.fish" "# >>> dotfiles-managed:fish.config >>>" "no"
  preserve_tail_case "fish-preserve-tail" "fish-config" "$tmp_root/fish-preserve-tail/home/.config/fish/config.fish" "# <<< dotfiles-managed:fish.config <<<" $'set -gx FNM_DIR "$HOME/.fnm"\n# installer line' 'set -gx FNM_DIR "$HOME/.fnm"'
  store_symlink_case "fish-store-symlink-repair" "fish-config" "$tmp_root/fish-store-symlink-repair/home/.config/fish/config.fish" "# >>> dotfiles-managed:fish.config >>>" "/nix/store/fake-hm-fish-config"

  test_existing_zshrc_link_remains_untouched
  test_directory_target_is_rejected

  echo "test: summary pass=$pass_count fail=$fail_count"

  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
