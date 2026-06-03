#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERMINAL_UX_ZSH="$ROOT/apps/shell/terminal-ux.zsh"

if [[ ! -f $TERMINAL_UX_ZSH ]]; then
  echo "test: terminal UX script not found: $TERMINAL_UX_ZSH" >&2
  exit 1
fi

zsh_bin="${ZSH_BIN:-$(command -v zsh || true)}"
if [[ -z $zsh_bin ]]; then
  echo "test: zsh not found" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/terminal-ux.XXXXXX")"
tmp_root="$(cd "$tmp_root" && pwd)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
work_dir="$home_dir/project/subdir"
runner="$tmp_root/run.zsh"
output_file="$tmp_root/output"

mkdir -p "$work_dir"

cat >"$runner" <<'EOF_RUNNER'
set -e

cd "$DOTFILES_TEST_WORK_DIR"
source "$DOTFILES_TEST_TERMINAL_UX_ZSH"

printf 'display=%s\n' "$(_dotfiles_terminal_display_dir "$PWD")"
printf 'cwd_title=%s\n' "$(_dotfiles_terminal_cwd_title)"
printf 'command_title=%s\n' "$(_dotfiles_terminal_command_title $'printf hello\nprintf ignored')"
printf 'clean=%s\n' "$(_dotfiles_terminal_clean_title $'bad\033title\aclean\nline')"

DOTFILES_TERMINAL_TITLE_FORCE=1 TERM=xterm-256color _dotfiles_terminal_set_title "forced title"
printf '\n'
DOTFILES_TERMINAL_TITLE_FORCE=1 DOTFILES_TERMINAL_TITLE=0 TERM=xterm-256color _dotfiles_terminal_set_title "disabled title"
printf 'disabled_done\n'
EOF_RUNNER

printf 'test: running terminal UX test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! env -i \
  HOME="$home_dir" \
  PATH="/usr/bin:/bin" \
  DOTFILES_TEST_WORK_DIR="$work_dir" \
  DOTFILES_TEST_TERMINAL_UX_ZSH="$TERMINAL_UX_ZSH" \
  "$zsh_bin" "$runner" >"$output_file"; then
  echo "FAIL: terminal UX zsh runner failed" >&2
  cat "$output_file" >&2 || true
  exit 1
fi

if ! grep -Fqx "display=~/project/subdir" "$output_file"; then
  echo "FAIL: display dir did not shorten HOME path" >&2
  cat "$output_file" >&2
  exit 1
fi

if ! grep -Fqx "cwd_title=subdir - ~/project/subdir" "$output_file"; then
  echo "FAIL: cwd terminal title is unexpected" >&2
  cat "$output_file" >&2
  exit 1
fi

if ! grep -Fqx "command_title=printf hello - subdir" "$output_file"; then
  echo "FAIL: command terminal title did not collapse multiline command" >&2
  cat "$output_file" >&2
  exit 1
fi

if ! grep -Fqx "clean=badtitleclean line" "$output_file"; then
  echo "FAIL: terminal title cleaner did not remove control characters" >&2
  cat "$output_file" >&2
  exit 1
fi

if ! grep -Fq $'\033]0;forced title\a' "$output_file"; then
  echo "FAIL: forced terminal title did not emit OSC title sequence" >&2
  od -An -tx1 "$output_file" >&2
  exit 1
fi

if grep -Fq "disabled title" "$output_file"; then
  echo "FAIL: disabled terminal title emitted output" >&2
  cat "$output_file" >&2
  exit 1
fi

echo "PASS: terminal UX"
