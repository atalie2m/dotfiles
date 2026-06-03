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
install_output="$tmp_root/install.out"
trap_output="$tmp_root/trap.out"
prompt_interrupt_output="$tmp_root/prompt-interrupt.out"
status_interrupt_output="$tmp_root/status-interrupt.out"

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

if ! env -i \
  HOME="$home_dir" \
  PATH="/usr/bin:/bin" \
  DOTFILES_TEST_TERMINAL_UX_ZSH="$TERMINAL_UX_ZSH" \
  DOTFILES_TEST_TRAP_OUTPUT="$trap_output" \
  DOTFILES_TEST_PROMPT_INTERRUPT_OUTPUT="$prompt_interrupt_output" \
  DOTFILES_TEST_STATUS_INTERRUPT_OUTPUT="$status_interrupt_output" \
  "$zsh_bin" -fic '
    source "$DOTFILES_TEST_TERMINAL_UX_ZSH"

    (( ${precmd_functions[(Ie)_dotfiles_terminal_precmd]} ))
    printf "precmd=%s zle=%s\n" "$?" "$options[zle]"

    (( ${preexec_functions[(Ie)_dotfiles_terminal_preexec]} ))
    printf "preexec=%s\n" "$?"

    functions TRAPINT >/dev/null 2>&1
    printf "trap=%s\n" "$?"

    _dotfiles_terminal_preexec "sleep 1"
    functions TRAPINT >/dev/null 2>&1
    printf "trap_after_preexec=%s command_active=%s\n" "$?" "${_dotfiles_terminal_command_active:-0}"

    true
    _dotfiles_terminal_precmd >/dev/null
    functions TRAPINT >/dev/null 2>&1
    printf "trap_after_precmd=%s command_active=%s\n" "$?" "${_dotfiles_terminal_command_active:-0}"

    ZLE_STATE=insert
    _dotfiles_terminal_prompt_interrupt_pending=0
    if TRAPINT 2 >"$DOTFILES_TEST_TRAP_OUTPUT"; then
      printf "trap_interrupt_status=0\n"
    else
      printf "trap_interrupt_status=%s\n" "$?"
    fi
    printf "trap_pending=%s\n" "${_dotfiles_terminal_prompt_interrupt_pending:-0}"

    _dotfiles_terminal_command_active=0
    if _dotfiles_terminal_visible_prompt_interrupt 0 >"$DOTFILES_TEST_PROMPT_INTERRUPT_OUTPUT"; then
      printf "prompt_interrupt_status=0\n"
    else
      printf "prompt_interrupt_status=%s\n" "$?"
    fi

    _dotfiles_terminal_command_active=0
    _dotfiles_terminal_prompt_interrupt_pending=0
    if _dotfiles_terminal_visible_prompt_interrupt 130 >"$DOTFILES_TEST_STATUS_INTERRUPT_OUTPUT"; then
      printf "status_interrupt_status=0\n"
    else
      printf "status_interrupt_status=%s\n" "$?"
    fi
  ' >"$install_output"; then
  echo "FAIL: terminal UX interactive install runner failed" >&2
  cat "$install_output" >&2 || true
  exit 1
fi

if ! grep -Fqx "precmd=0 zle=on" "$install_output"; then
  echo "FAIL: terminal UX precmd hook was not installed in interactive zsh" >&2
  cat "$install_output" >&2
  exit 1
fi

if ! grep -Fqx "preexec=0" "$install_output"; then
  echo "FAIL: terminal UX preexec hook was not installed in interactive zsh" >&2
  cat "$install_output" >&2
  exit 1
fi

if ! grep -Fqx "trap=0" "$install_output"; then
  echo "FAIL: visible interrupt trap was not installed in interactive zsh" >&2
  cat "$install_output" >&2
  exit 1
fi

if ! grep -Fqx "trap_after_preexec=1 command_active=1" "$install_output"; then
  echo "FAIL: visible interrupt trap was not removed for command execution" >&2
  cat "$install_output" >&2
  exit 1
fi

if ! grep -Fqx "trap_after_precmd=0 command_active=0" "$install_output"; then
  echo "FAIL: visible interrupt trap was not restored for prompt editing" >&2
  cat "$install_output" >&2
  exit 1
fi

if ! grep -Fqx "trap_interrupt_status=130" "$install_output"; then
  echo "FAIL: interrupt trap status is unexpected" >&2
  cat "$install_output" >&2
  exit 1
fi

if [[ -s $trap_output ]]; then
  echo "FAIL: interrupt trap emitted directly instead of deferring to precmd" >&2
  cat "$trap_output" >&2 || true
  exit 1
fi

if ! grep -Fqx "trap_pending=1" "$install_output"; then
  echo "FAIL: interrupt trap did not mark prompt interrupt pending" >&2
  cat "$install_output" >&2
  exit 1
fi

if ! grep -Fqx "prompt_interrupt_status=0" "$install_output"; then
  echo "FAIL: prompt interrupt status is unexpected" >&2
  cat "$install_output" >&2
  exit 1
fi

if [[ $(cat "$prompt_interrupt_output") != "^C" ]]; then
  echo "FAIL: prompt interrupt did not emit visible control marker" >&2
  cat "$prompt_interrupt_output" >&2 || true
  exit 1
fi

if ! grep -Fqx "status_interrupt_status=130" "$install_output"; then
  echo "FAIL: status-only interrupt return is unexpected" >&2
  cat "$install_output" >&2
  exit 1
fi

if [[ -s $status_interrupt_output ]]; then
  echo "FAIL: status-only interrupt emitted obsolete visible marker" >&2
  cat "$status_interrupt_output" >&2 || true
  exit 1
fi

echo "PASS: terminal UX"
