# shellcheck shell=zsh

_dotfiles_terminal_title_enabled() {
  emulate -L zsh

  [[ "${DOTFILES_TERMINAL_TITLE:-1}" != "0" ]] || return 1
  [[ "${TERM:-}" != "dumb" ]] || return 1
  [[ -t 1 || "${DOTFILES_TERMINAL_TITLE_FORCE:-0}" == "1" ]] || return 1
}

_dotfiles_terminal_clean_title() {
  emulate -L zsh

  local title="$1"
  title="${title//$'\e'/}"
  title="${title//$'\a'/}"
  title="${title//$'\r'/ }"
  title="${title//$'\n'/ }"
  print -r -- "$title"
}

_dotfiles_terminal_display_dir() {
  emulate -L zsh

  local dir="${1:-${PWD:-}}"

  if [[ -z "$dir" ]]; then
    print -r -- "?"
    return 0
  fi
  if [[ -n "${HOME:-}" && "$dir" == "$HOME" ]]; then
    print -r -- "~"
    return 0
  fi
  if [[ -n "${HOME:-}" && "$dir" == "$HOME/"* ]]; then
    print -r -- "~/${dir#$HOME/}"
    return 0
  fi

  print -r -- "$dir"
}

_dotfiles_terminal_cwd_title() {
  emulate -L zsh

  local cwd="${PWD:-}"
  local name="${cwd:t}"

  if [[ -z "$name" ]]; then
    name="/"
  fi

  print -r -- "$name - $(_dotfiles_terminal_display_dir "$cwd")"
}

_dotfiles_terminal_command_title() {
  emulate -L zsh

  local command="$1"
  local cwd="${PWD:-}"
  local name="${cwd:t}"

  if [[ -z "$name" ]]; then
    name="/"
  fi

  command="${command//$'\r'/ }"
  command="${command%%$'\n'*}"
  if (( ${#command} > 90 )); then
    command="${command[1,87]}..."
  fi

  print -r -- "$command - $name"
}

_dotfiles_terminal_set_title() {
  emulate -L zsh

  _dotfiles_terminal_title_enabled || return 0

  local title
  title="$(_dotfiles_terminal_clean_title "$1")"
  printf '\033]0;%s\a' "$title"
}

_dotfiles_terminal_visible_prompt_interrupt() {
  emulate -L zsh

  local return_status="${1:-0}"

  if [[
    "${DOTFILES_TERMINAL_VISIBLE_INTERRUPT:-1}" != "0" &&
    "${_dotfiles_terminal_prompt_interrupt_pending:-0}" == "1" &&
    "${_dotfiles_terminal_command_active:-0}" != "1"
  ]]; then
    print -r -- '^C'
  fi

  _dotfiles_terminal_prompt_interrupt_pending=0
  return "$return_status"
}

_dotfiles_terminal_note_interrupt() {
  emulate -L zsh

  local interrupt_signal="${1:-2}"

  if [[ "${DOTFILES_TERMINAL_VISIBLE_INTERRUPT:-1}" != "0" && -n "${ZLE_STATE:-}" ]]; then
    _dotfiles_terminal_prompt_interrupt_pending=1
    zle .send-break 2>/dev/null || true
  fi

  return $((128 + interrupt_signal))
}

_dotfiles_terminal_install_visible_interrupt() {
  emulate -L zsh

  [[ "$options[zle]" = on ]] || return 0

  setopt no_local_traps
  TRAPINT() {
    _dotfiles_terminal_note_interrupt "${1:-2}"
  }
}

_dotfiles_terminal_uninstall_visible_interrupt() {
  emulate -L zsh

  unfunction TRAPINT 2>/dev/null || true
}

_dotfiles_terminal_precmd() {
  emulate -L zsh

  local last_status="$?"

  _dotfiles_terminal_visible_prompt_interrupt "$last_status"
  _dotfiles_terminal_command_active=0
  _dotfiles_terminal_install_visible_interrupt
  _dotfiles_terminal_set_title "$(_dotfiles_terminal_cwd_title)"
  return "$last_status"
}

_dotfiles_terminal_preexec() {
  emulate -L zsh

  _dotfiles_terminal_command_active=1
  _dotfiles_terminal_uninstall_visible_interrupt
  _dotfiles_terminal_set_title "$(_dotfiles_terminal_command_title "$1")"
}

_dotfiles_terminal_install_edit_command_line() {
  emulate -L zsh

  [[ "$options[zle]" = on ]] || return 0

  autoload -Uz edit-command-line
  zle -N edit-command-line
  bindkey -M emacs '^X^E' edit-command-line
  bindkey -M viins '^X^E' edit-command-line
  bindkey -M vicmd '^X^E' edit-command-line
}

_dotfiles_terminal_install_title_hooks() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _dotfiles_terminal_precmd
  add-zsh-hook preexec _dotfiles_terminal_preexec
}

_dotfiles_terminal_install() {
  emulate -L zsh

  _dotfiles_terminal_install_title_hooks
  _dotfiles_terminal_install_edit_command_line
  _dotfiles_terminal_install_visible_interrupt
}

_dotfiles_terminal_install
