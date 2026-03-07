#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="zshrc-compat"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/zshrc-compat.sh --check
  bash scripts/zshrc-compat.sh --apply
  bash scripts/zshrc-compat.sh --migrate

Description:
  Keep ~/.zshrc aligned with the writable runtime wrapper at ~/.nix/.zshrc.

Modes:
  --check    Report whether ~/.zshrc is the expected compat symlink
  --apply    Create the compat symlink for safe states only
  --migrate  Move an existing regular-file ~/.zshrc into ~/.nix/.zshrc, then replace it with the compat symlink
USAGE
}

set_repo_root

mode="check"
mode_explicit=0
root_zshrc="$HOME/.zshrc"
compat_target_rel=".nix/.zshrc"
compat_target_path="$HOME/$compat_target_rel"
migration_marker="# migrated from ~/.zshrc by zshrc-compat"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zshrc-compat.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

new_tmp_file() {
  mktemp "$tmp_dir/file.XXXXXX"
}

set_mode() {
  local next_mode="$1"

  if [[ $mode_explicit -eq 1 && $mode != "$next_mode" ]]; then
    die "choose only one of --check, --apply, or --migrate"
  fi

  mode="$next_mode"
  mode_explicit=1
}

ensure_runtime_wrapper() {
  if bash "$SCRIPT_DIR/sync.sh" shell --apply --item zsh-zdotdir >/dev/null; then
    return 0
  fi

  log "failed to prepare writable runtime wrapper: $compat_target_path"
  return 1
}

current_status() {
  if [[ -L $root_zshrc ]]; then
    local link_target
    link_target="$(readlink "$root_zshrc" || true)"
    if [[ $link_target == "$compat_target_rel" ]]; then
      printf '%s|%s\n' "in-sync" "$link_target"
    else
      printf '%s|%s\n' "conflict" "symlink:$link_target"
    fi
    return 0
  fi

  if [[ ! -e $root_zshrc ]]; then
    printf '%s|%s\n' "missing" ""
    return 0
  fi

  if [[ -f $root_zshrc ]]; then
    printf '%s|%s\n' "conflict" "regular-file"
    return 0
  fi

  if [[ -d $root_zshrc ]]; then
    printf '%s|%s\n' "conflict" "directory"
    return 0
  fi

  printf '%s|%s\n' "conflict" "special-file"
}

print_status() {
  local status="$1"
  local detail="$2"

  case "$status" in
  in-sync)
    log "summary: status=in-sync path=$root_zshrc target=$compat_target_rel"
    ;;
  missing)
    log "summary: status=missing path=$root_zshrc"
    ;;
  conflict)
    if [[ -n $detail ]]; then
      log "summary: status=conflict path=$root_zshrc detail=$detail"
    else
      log "summary: status=conflict path=$root_zshrc"
    fi
    ;;
  esac
}

append_migrated_tail() {
  local source_file="$1"
  local tmp_source tmp_out

  tmp_source="$(new_tmp_file)"
  canonicalize_text_to_file "$source_file" "$tmp_source" || return 1

  if [[ ! -s $tmp_source ]]; then
    rm -f "$tmp_source"
    return 0
  fi

  if [[ -f $compat_target_path ]] && text_file_contains_exact_line "$migration_marker" "$compat_target_path"; then
    rm -f "$tmp_source"
    die "refusing to migrate: '$migration_marker' already exists in $compat_target_path"
  fi

  tmp_out="$(new_tmp_file)"
  if [[ -f $compat_target_path ]]; then
    cat "$compat_target_path" >"$tmp_out"
    if [[ -s $compat_target_path ]]; then
      printf '\n' >>"$tmp_out"
    fi
  fi

  printf '%s\n' "$migration_marker" >>"$tmp_out"
  cat "$tmp_source" >>"$tmp_out"

  mkdir -p "$(dirname "$compat_target_path")"
  mv "$tmp_out" "$compat_target_path"
  rm -f "$tmp_source"
}

create_compat_symlink() {
  mkdir -p "$(dirname "$compat_target_path")"
  ln -sfn "$compat_target_rel" "$root_zshrc"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    set_mode "check"
    shift
    ;;
  --apply)
    set_mode "apply"
    shift
    ;;
  --migrate)
    set_mode "migrate"
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    die "unknown option for zshrc-compat: $1"
    ;;
  esac
done

IFS='|' read -r status detail <<<"$(current_status)"

case "$mode" in
check)
  print_status "$status" "$detail"
  [[ $status == "in-sync" ]]
  ;;
apply)
  case "$status" in
  in-sync)
    print_status "$status" "$detail"
    exit 0
    ;;
  missing)
    ensure_runtime_wrapper || exit 1
    create_compat_symlink
    log "created compat symlink: $root_zshrc -> $compat_target_rel"
    print_status "in-sync" "$compat_target_rel"
    exit 0
    ;;
  conflict)
    print_status "$status" "$detail"
    log "apply refused: run --migrate for a regular-file ~/.zshrc, or resolve the conflict manually"
    exit 1
    ;;
  esac
  ;;
migrate)
  case "$status" in
  in-sync)
    print_status "$status" "$detail"
    exit 0
    ;;
  missing)
    ensure_runtime_wrapper || exit 1
    create_compat_symlink
    log "created compat symlink: $root_zshrc -> $compat_target_rel"
    print_status "in-sync" "$compat_target_rel"
    exit 0
    ;;
  conflict)
    if [[ $detail != "regular-file" ]]; then
      print_status "$status" "$detail"
      die "migrate only supports a regular-file ~/.zshrc; resolve this conflict manually"
    fi

    ensure_runtime_wrapper || exit 1

    timestamp="$(date +%Y%m%d%H%M%S)"
    backup_path="$HOME/.zshrc.pre-dotfiles-compat.${timestamp}.bak"
    cp "$root_zshrc" "$backup_path"
    append_migrated_tail "$root_zshrc"
    rm -f "$root_zshrc"
    create_compat_symlink
    log "migrated ~/.zshrc into $compat_target_path"
    log "backup: $backup_path"
    print_status "in-sync" "$compat_target_rel"
    exit 0
    ;;
  esac
  ;;
esac
