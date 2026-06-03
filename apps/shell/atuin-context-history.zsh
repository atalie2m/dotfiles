# shellcheck shell=zsh

_dotfiles_atuin_context_display_dir() {
  emulate -L zsh

  local dir="$1"

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

_dotfiles_atuin_context_parent_label() {
  emulate -L zsh

  local depth="$1"
  local marker=".."
  local index

  for (( index = 1; index < depth; index++ )); do
    marker="../$marker"
  done

  print -r -- "parent:$marker"
}

_dotfiles_atuin_context_emit_bucket() {
  emulate -L zsh

  local tmpdir="$1"
  local label="$2"
  local limit="$3"
  shift 3

  local -a query_args=()
  if [[ -n "${DOTFILES_ATUIN_CONTEXT_QUERY:-}" ]]; then
    query_args=("$DOTFILES_ATUIN_CONTEXT_QUERY")
  fi

  local record dir command id display_dir display_command
  while IFS= read -r -d $'\0' record; do
    [[ "$record" == *$'\t'* ]] || continue

    dir="${record%%$'\t'*}"
    command="${record#*$'\t'}"
    [[ -n "$command" ]] || continue
    [[ -z "${_dotfiles_atuin_context_seen[$command]+x}" ]] || continue

    _dotfiles_atuin_context_seen[$command]=1
    _dotfiles_atuin_context_seq=$(( _dotfiles_atuin_context_seq + 1 ))
    id="$(printf '%06d' "$_dotfiles_atuin_context_seq")"

    print -rn -- "$command" >"$tmpdir/command-$id"

    display_dir="$(_dotfiles_atuin_context_display_dir "$dir")"
    display_command="$command"
    display_command="${display_command//$'\t'/  }"
    display_command="${display_command//$'\n'/\\n}"

    printf '%s\t%s\t%s\t%s\n' "$id" "$label" "$display_dir" "$display_command"
  done < <(
    ATUIN_LOG=error command atuin search \
      --limit "$limit" \
      --format $'{directory}\t{command}' \
      --print0 \
      "$@" \
      "${query_args[@]}" 2>/dev/null
  )
}

_dotfiles_atuin_context_build_candidates() {
  emulate -L zsh

  local tmpdir="$1"
  local query="${2:-}"
  local current_limit="${DOTFILES_ATUIN_CONTEXT_CURRENT_LIMIT:-120}"
  local workspace_limit="${DOTFILES_ATUIN_CONTEXT_WORKSPACE_LIMIT:-160}"
  local parent_limit="${DOTFILES_ATUIN_CONTEXT_PARENT_LIMIT:-80}"
  local global_limit="${DOTFILES_ATUIN_CONTEXT_GLOBAL_LIMIT:-240}"
  local parent_depth="${DOTFILES_ATUIN_CONTEXT_PARENT_DEPTH:-4}"

  typeset -gA _dotfiles_atuin_context_seen
  typeset -g _dotfiles_atuin_context_seq
  typeset -g DOTFILES_ATUIN_CONTEXT_QUERY
  _dotfiles_atuin_context_seen=()
  _dotfiles_atuin_context_seq=0
  DOTFILES_ATUIN_CONTEXT_QUERY="$query"

  _dotfiles_atuin_context_emit_bucket "$tmpdir" "cwd" "$current_limit" --cwd "$PWD"
  _dotfiles_atuin_context_emit_bucket "$tmpdir" "workspace" "$workspace_limit" --filter-mode workspace

  local parent="$PWD"
  local depth label
  for (( depth = 1; depth <= parent_depth; depth++ )); do
    parent="${parent:h}"
    [[ -n "$parent" && "$parent" != "/" ]] || break

    label="$(_dotfiles_atuin_context_parent_label "$depth")"
    _dotfiles_atuin_context_emit_bucket "$tmpdir" "$label" "$parent_limit" --cwd "$parent"
  done

  _dotfiles_atuin_context_emit_bucket "$tmpdir" "global" "$global_limit" --filter-mode global
}

_dotfiles_atuin_context_fallback_search() {
  emulate -L zsh

  if zle -l atuin-search >/dev/null 2>&1; then
    zle atuin-search
  fi
}

_dotfiles_atuin_context_search_widget() {
  emulate -L zsh
  zle -I

  if ! command -v atuin >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1; then
    _dotfiles_atuin_context_fallback_search
    return
  fi
  if [[ "$BUFFER" == *$'\n'* ]]; then
    _dotfiles_atuin_context_fallback_search
    return
  fi

  local tmpdir candidates selected id command_file
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-atuin-history.XXXXXX")" || {
    _dotfiles_atuin_context_fallback_search
    return
  }
  candidates="$tmpdir/candidates"

  _dotfiles_atuin_context_build_candidates "$tmpdir" "$BUFFER" >"$candidates"

  if [[ ! -s "$candidates" ]]; then
    command rm -rf -- "$tmpdir"
    _dotfiles_atuin_context_fallback_search
    return
  fi

  selected="$(
    command fzf \
      --height="${DOTFILES_ATUIN_CONTEXT_FZF_HEIGHT:-60%}" \
      --layout=reverse \
      --border=rounded \
      --prompt="history> " \
      --delimiter=$'\t' \
      --with-nth=2,4,3 \
      --nth=2,3,4 \
      --no-sort \
      --query="$BUFFER" \
      --header="cwd, workspace, parent directories, then global" \
      <"$candidates"
  )" || selected=""

  if [[ -n "$selected" ]]; then
    id="${selected%%$'\t'*}"
    command_file="$tmpdir/command-$id"
    if [[ -f "$command_file" ]]; then
      LBUFFER="$(<"$command_file")"
      RBUFFER=""
    fi
  fi

  command rm -rf -- "$tmpdir"
  zle reset-prompt
}

_dotfiles_atuin_context_install() {
  emulate -L zsh

  [[ "$options[zle]" = on ]] || return 0

  zle -N dotfiles-atuin-context-search _dotfiles_atuin_context_search_widget
  bindkey -M emacs '^r' dotfiles-atuin-context-search
  bindkey -M viins '^r' dotfiles-atuin-context-search
}

_dotfiles_atuin_context_install
