#!/usr/bin/env bash

list_target_ids() {
  printf '%s\n' "zsh-zdotdir"
  printf '%s\n' "bash-rc"
}

target_meta_for_id() {
  local current_managed_dir="${managed_dir:?managed_dir is required}"

  case "$1" in
  zsh-zdotdir)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "zsh" "block" "$HOME/.nix/.zshrc" "$current_managed_dir/zdotdir.zshrc.block.sh" \
      "# >>> dotfiles-managed:zdotdir.zshrc >>>" "# <<< dotfiles-managed:zdotdir.zshrc <<<"
    ;;
  bash-rc)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "bash" "block" "$HOME/.bashrc" "$current_managed_dir/bashrc.entrypoint.block.sh" \
      "# >>> dotfiles-managed:bashrc >>>" "# <<< dotfiles-managed:bashrc <<<"
    ;;
  *)
    return 1
    ;;
  esac
}

target_selected() {
  local id="$1"
  local shell_name="$2"

  if [[ -n $item_filter && $id != "$item_filter" ]]; then
    return 1
  fi

  if [[ -z $group_filter || $group_filter == "all" ]]; then
    return 0
  fi

  case ",$group_filter," in
  *",$shell_name,"*) return 0 ;;
  *) return 1 ;;
  esac
}

path_shape_for_target() {
  local path="$1"
  local link_target=""

  if [[ -L $path ]]; then
    link_target="$(readlink "$path" || true)"
    if [[ $link_target == /nix/store/* ]]; then
      printf '%s|%s\n' "symlink-store" "$link_target"
      return 0
    fi
    if [[ -f $path ]]; then
      printf '%s|%s\n' "symlink-regular" "$link_target"
      return 0
    fi
    if [[ -d $path ]]; then
      printf '%s|%s\n' "symlink-directory" "$link_target"
      return 0
    fi
    if [[ -e $path ]]; then
      printf '%s|%s\n' "symlink-special" "$link_target"
      return 0
    fi
    printf '%s|%s\n' "symlink-broken" "$link_target"
    return 0
  fi

  if [[ -f $path ]]; then
    printf 'regular|\n'
    return 0
  fi
  if [[ -d $path ]]; then
    printf 'directory|\n'
    return 0
  fi
  if [[ -e $path ]]; then
    printf 'special|\n'
    return 0
  fi

  printf 'missing|\n'
}
