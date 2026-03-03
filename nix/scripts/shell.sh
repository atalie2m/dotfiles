#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="shell"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"
# shellcheck source=sync-core.sh
source_dotfiles_script "sync-core.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- shell sync --check [--details] [--diff] [--shell <zsh|bash|fish|all>] [--target <id>] [--managed-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- shell sync --apply [--details] [--diff] [--shell <zsh|bash|fish|all>] [--target <id>] [--managed-dir <path>] [--state-dir <path>] [--force]
  nix run .#dotfiles -- shell sync --adopt [--details] [--diff] [--shell <zsh|bash|fish|all>] [--target <id>] [--managed-dir <path>] [--state-dir <path>] [--in-place] [--force] [--output-dir <path>]
  nix run .#dotfiles -- shell sync --forget [--shell <zsh|bash|fish|all>] [--target <id>] [--state-dir <path>]

Description:
  Manage shell config with lastApplied 3-way status.
  - zsh-zdotdir: managed block in ~/.nix/.zshrc (runtime entrypoint)
  - bash-rc: managed block in ~/.bashrc (runtime entrypoint)
  - bash-local: managed block in ~/.bashrc.local
  - fish-config: managed block in ~/.config/fish/config.fish (runtime entrypoint)
  - fish-core: whole file at ~/.config/fish/conf.d/00-dotfiles.fish

Options:
  --check              Detect drift/missing/invalid (default mode)
  --apply              Apply desired managed content to local targets
  --adopt              Export current local managed content for drifted targets
  --forget             Remove last-applied hash state
  --shell <name>       Filter targets by shell (repeatable, default: all)
  --target <id>        Filter one target id (zsh-zdotdir, bash-rc, bash-local, fish-config, fish-core)
  --details            Print concise per-target details
  --diff               Print unified diff (desired vs current)
  --managed-dir <path> Desired managed content directory (default: <repo>/apps/shell/managed)
  --state-dir <path>   Last-applied hash directory (default: $XDG_STATE_HOME/dotfiles/shell/blocks)
  --in-place           With --adopt, overwrite desired files in place
  --force              With --apply, allow overwrite on drift/conflict; with --adopt --in-place, allow conflict overwrite
  --output-dir <path>  With --adopt (staging mode), directory for exported managed content
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

subcommand="$1"
shift

if [[ $subcommand != "sync" ]]; then
  die "unknown shell subcommand: $subcommand"
fi

mode="check"
shell_filter=""
target_filter=""
details=0
show_diff=0
in_place=0
force=0
output_dir=""
default_managed_dir=1

set_repo_root
managed_dir="$ROOT/apps/shell/managed"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/shell/blocks"

append_shell_filter() {
  local shell_name="$1"

  if [[ $shell_filter == "all" ]]; then
    return 0
  fi

  if [[ -z $shell_filter ]]; then
    shell_filter="$shell_name"
    return 0
  fi

  case ",$shell_filter," in
  *",$shell_name,"*) ;;
  *)
    shell_filter="$shell_filter,$shell_name"
    ;;
  esac
}

sync_cli_parse_script_option() {
  case "$1" in
  --shell)
    [[ $# -lt 2 ]] && die "missing value for --shell"
    case "$2" in
    zsh | bash | fish)
      append_shell_filter "$2"
      ;;
    all)
      shell_filter="all"
      ;;
    *)
      die "invalid --shell value: $2 (expected zsh, bash, fish, all)"
      ;;
    esac
    sync_core_cli_consumed=2
    return 0
    ;;
  --target)
    [[ $# -lt 2 ]] && die "missing value for --target"
    target_filter="$2"
    sync_core_cli_consumed=2
    return 0
    ;;
  --managed-dir)
    [[ $# -lt 2 ]] && die "missing value for --managed-dir"
    managed_dir="$2"
    default_managed_dir=0
    sync_core_cli_consumed=2
    return 0
    ;;
  --state-dir)
    [[ $# -lt 2 ]] && die "missing value for --state-dir"
    state_dir="$2"
    sync_core_cli_consumed=2
    return 0
    ;;
  esac

  return 1
}

sync_core_parse_cli_args 1 "$@"

if [[ $default_managed_dir -eq 1 ]]; then
  worktree_root="$(resolve_repo_worktree_root_for "apps/shell/managed" || true)"
  if [[ -n $worktree_root ]]; then
    ROOT="$worktree_root"
    managed_dir="$ROOT/apps/shell/managed"
  fi
fi

sync_core_validate_adopt_flags "$mode" "$in_place" "$output_dir"
sync_core_validate_force_usage "$mode" "$in_place" "$force" 1 "--force is only valid with --apply or --adopt --in-place"

if [[ $mode != "forget" && ! -d $managed_dir ]]; then
  die "managed dir not found: $managed_dir"
fi

list_target_ids() {
  printf '%s\n' "zsh-zdotdir"
  printf '%s\n' "bash-rc"
  printf '%s\n' "bash-local"
  printf '%s\n' "fish-config"
  printf '%s\n' "fish-core"
}

target_shell_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "zsh" ;;
  bash-rc) printf '%s\n' "bash" ;;
  bash-local) printf '%s\n' "bash" ;;
  fish-config) printf '%s\n' "fish" ;;
  fish-core) printf '%s\n' "fish" ;;
  *)
    return 1
    ;;
  esac
}

target_type_for_id() {
  case "$1" in
  fish-core) printf '%s\n' "file" ;;
  zsh-zdotdir | bash-rc | bash-local | fish-config) printf '%s\n' "block" ;;
  *)
    return 1
    ;;
  esac
}

target_actual_path_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "$HOME/.nix/.zshrc" ;;
  bash-rc) printf '%s\n' "$HOME/.bashrc" ;;
  bash-local) printf '%s\n' "$HOME/.bashrc.local" ;;
  fish-config) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
  fish-core) printf '%s\n' "$HOME/.config/fish/conf.d/00-dotfiles.fish" ;;
  *)
    return 1
    ;;
  esac
}

target_desired_path_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "$managed_dir/zdotdir.zshrc.block.sh" ;;
  bash-rc) printf '%s\n' "$managed_dir/bashrc.entrypoint.block.sh" ;;
  bash-local) printf '%s\n' "$managed_dir/bashrc.local.block.sh" ;;
  fish-config) printf '%s\n' "$managed_dir/fish.config.block.fish" ;;
  fish-core) printf '%s\n' "$managed_dir/00-dotfiles.fish" ;;
  *)
    return 1
    ;;
  esac
}

target_begin_marker_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "# >>> dotfiles-managed:zdotdir.zshrc >>>" ;;
  bash-rc) printf '%s\n' "# >>> dotfiles-managed:bashrc >>>" ;;
  bash-local) printf '%s\n' "# >>> dotfiles-managed:bashrc.local >>>" ;;
  fish-config) printf '%s\n' "# >>> dotfiles-managed:fish.config >>>" ;;
  fish-core) printf '%s\n' "" ;;
  *)
    return 1
    ;;
  esac
}

target_end_marker_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "# <<< dotfiles-managed:zdotdir.zshrc <<<" ;;
  bash-rc) printf '%s\n' "# <<< dotfiles-managed:bashrc <<<" ;;
  bash-local) printf '%s\n' "# <<< dotfiles-managed:bashrc.local <<<" ;;
  fish-config) printf '%s\n' "# <<< dotfiles-managed:fish.config <<<" ;;
  fish-core) printf '%s\n' "" ;;
  *)
    return 1
    ;;
  esac
}

target_selected() {
  local id="$1"
  local shell_name

  if [[ -n $target_filter && $id != "$target_filter" ]]; then
    return 1
  fi

  if [[ -z $shell_filter || $shell_filter == "all" ]]; then
    return 0
  fi

  shell_name="$(target_shell_for_id "$id" || true)"
  if [[ -z $shell_name ]]; then
    return 1
  fi

  case ",$shell_filter," in
  *",$shell_name,"*) return 0 ;;
  *) return 1 ;;
  esac
}

canonicalize_text_to_file() {
  local source_file="$1"
  local output_file="$2"
  /usr/bin/awk '{ sub(/\r$/, ""); print }' "$source_file" >"$output_file"
}

extract_managed_block() {
  local source_file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local output_file="$4"

  [[ -f $source_file ]] || return 2

  if /usr/bin/awk -v begin="$begin_marker" -v end="$end_marker" '
    BEGIN {
      beginCount = 0
      endCount = 0
      inBlock = 0
    }
    $0 == begin {
      beginCount++
      if (beginCount > 1 || inBlock == 1) {
        exit 3
      }
      inBlock = 1
      next
    }
    $0 == end {
      endCount++
      if (inBlock == 0 || endCount > 1) {
        exit 3
      }
      inBlock = 0
      next
    }
    inBlock == 1 {
      print
    }
    END {
      if (beginCount == 0 && endCount == 0) {
        exit 2
      }
      if (beginCount == 1 && endCount == 1 && inBlock == 0) {
        exit 0
      }
      exit 3
    }
  ' "$source_file" >"$output_file"; then
    return 0
  else
    case "$?" in
    2) return 2 ;;
    3) return 3 ;;
    *) return 3 ;;
    esac
  fi
}

extract_desired_content_for_target() {
  local id="$1"
  local output_file="$2"
  local desired_path

  desired_path="$(target_desired_path_for_id "$id")"
  [[ -f $desired_path ]] || return 1
  canonicalize_text_to_file "$desired_path" "$output_file"
}

extract_actual_content_for_target() {
  local id="$1"
  local output_file="$2"
  local target_type actual_path begin_marker end_marker tmp_block

  target_type="$(target_type_for_id "$id")"
  actual_path="$(target_actual_path_for_id "$id")"

  if [[ $target_type == "file" ]]; then
    [[ -f $actual_path ]] || return 2
    canonicalize_text_to_file "$actual_path" "$output_file"
    return 0
  fi

  begin_marker="$(target_begin_marker_for_id "$id")"
  end_marker="$(target_end_marker_for_id "$id")"
  tmp_block="$(mktemp)"
  if extract_managed_block "$actual_path" "$begin_marker" "$end_marker" "$tmp_block"; then
    canonicalize_text_to_file "$tmp_block" "$output_file"
    rm -f "$tmp_block"
    return 0
  else
    local rc=$?
    rm -f "$tmp_block"
    return "$rc"
  fi
}

print_target_diff() {
  local id="$1"
  local desired_tmp actual_tmp

  desired_tmp="$(mktemp)"
  actual_tmp="$(mktemp)"

  if ! extract_desired_content_for_target "$id" "$desired_tmp"; then
    rm -f "$desired_tmp" "$actual_tmp"
    return 1
  fi

  if ! extract_actual_content_for_target "$id" "$actual_tmp"; then
    rm -f "$desired_tmp" "$actual_tmp"
    return 1
  fi

  log "diff: $id"
  /usr/bin/diff -u "$desired_tmp" "$actual_tmp" || true
  rm -f "$desired_tmp" "$actual_tmp"
  return 0
}

print_target_details() {
  local id="$1"
  local desired_path="$2"
  local actual_path="$3"
  local target_type

  target_type="$(target_type_for_id "$id")"
  log "details: $id"
  log "  type: $target_type"
  log "  desired: $desired_path"
  log "  actual: $actual_path"
}

export_actual_to_path() {
  local id="$1"
  local destination="$2"
  local tmp_actual

  tmp_actual="$(mktemp)"
  if ! extract_actual_content_for_target "$id" "$tmp_actual"; then
    rm -f "$tmp_actual"
    return 1
  fi

  mkdir -p "$(dirname "$destination")"
  mv "$tmp_actual" "$destination"
  return 0
}

replace_managed_block_in_file() {
  local source_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local output_file="$5"

  /usr/bin/awk -v begin="$begin_marker" -v end="$end_marker" -v desired="$desired_file" '
    BEGIN {
      beginCount = 0
      endCount = 0
      inBlock = 0
    }
    $0 == begin {
      beginCount++
      if (beginCount > 1 || inBlock == 1) {
        exit 3
      }
      print $0
      while ((getline line < desired) > 0) {
        sub(/\r$/, "", line)
        print line
      }
      close(desired)
      inBlock = 1
      next
    }
    $0 == end {
      endCount++
      if (inBlock == 0 || endCount > 1) {
        exit 3
      }
      inBlock = 0
      print $0
      next
    }
    inBlock == 0 {
      print
    }
    END {
      if (beginCount == 0 && endCount == 0) {
        exit 2
      }
      if (beginCount == 1 && endCount == 1 && inBlock == 0) {
        exit 0
      }
      exit 3
    }
  ' "$source_file" >"$output_file"
}

write_block_to_file() {
  local target_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local tmp_out rc last_char

  tmp_out="$(mktemp)"

  if [[ -f $target_file ]]; then
    if replace_managed_block_in_file "$target_file" "$desired_file" "$begin_marker" "$end_marker" "$tmp_out"; then
      :
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then
        cat "$target_file" >"$tmp_out"
        if [[ -s $target_file ]]; then
          last_char="$(tail -c 1 "$target_file" 2>/dev/null || true)"
          if [[ $last_char != $'\n' ]]; then
            printf '\n' >>"$tmp_out"
          fi
          printf '\n' >>"$tmp_out"
        fi
        printf '%s\n' "$begin_marker" >>"$tmp_out"
        /usr/bin/awk '{ sub(/\r$/, ""); print }' "$desired_file" >>"$tmp_out"
        printf '%s\n' "$end_marker" >>"$tmp_out"
      else
        rm -f "$tmp_out"
        return 1
      fi
    fi
  else
    printf '%s\n' "$begin_marker" >"$tmp_out"
    /usr/bin/awk '{ sub(/\r$/, ""); print }' "$desired_file" >>"$tmp_out"
    printf '%s\n' "$end_marker" >>"$tmp_out"
  fi

  mkdir -p "$(dirname "$target_file")"
  mv "$tmp_out" "$target_file"
  return 0
}

write_fresh_block_file() {
  local target_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local tmp_out

  tmp_out="$(mktemp)"
  printf '%s\n' "$begin_marker" >"$tmp_out"
  /usr/bin/awk '{ sub(/\r$/, ""); print }' "$desired_file" >>"$tmp_out"
  printf '%s\n' "$end_marker" >>"$tmp_out"

  mkdir -p "$(dirname "$target_file")"
  mv "$tmp_out" "$target_file"
  return 0
}

write_entrypoint_file() {
  local target_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local tmp_out tmp_replaced rc link_target preserve_existing

  if [[ -f $target_file || -L $target_file ]]; then
    tmp_replaced="$(mktemp)"
    if replace_managed_block_in_file "$target_file" "$desired_file" "$begin_marker" "$end_marker" "$tmp_replaced"; then
      mkdir -p "$(dirname "$target_file")"
      mv "$tmp_replaced" "$target_file"
      return 0
    else
      rc=$?
      rm -f "$tmp_replaced"
      if [[ $rc -ne 2 ]]; then
        return 1
      fi
    fi
  fi

  tmp_out="$(mktemp)"
  printf '%s\n' "$begin_marker" >"$tmp_out"
  /usr/bin/awk '{ sub(/\r$/, ""); print }' "$desired_file" >>"$tmp_out"
  printf '%s\n' "$end_marker" >>"$tmp_out"

  preserve_existing=0
  if [[ -f $target_file ]]; then
    preserve_existing=1
  elif [[ -L $target_file ]]; then
    link_target="$(readlink "$target_file" || true)"
    if [[ $link_target != /nix/store/* && -f $target_file ]]; then
      preserve_existing=1
    fi
  fi

  if [[ $preserve_existing -eq 1 ]]; then
    printf '\n' >>"$tmp_out"
    /usr/bin/awk '{ sub(/\r$/, ""); print }' "$target_file" >>"$tmp_out"
  fi

  mkdir -p "$(dirname "$target_file")"
  mv "$tmp_out" "$target_file"
  return 0
}

write_target_from_desired() {
  local id="$1"
  local target_type desired_path actual_path begin_marker end_marker tmp_desired link_target

  target_type="$(target_type_for_id "$id")"
  desired_path="$(target_desired_path_for_id "$id")"
  actual_path="$(target_actual_path_for_id "$id")"

  if [[ $target_type == "file" ]]; then
    tmp_desired="$(mktemp)"
    if ! extract_desired_content_for_target "$id" "$tmp_desired"; then
      rm -f "$tmp_desired"
      return 1
    fi
    mkdir -p "$(dirname "$actual_path")"
    mv "$tmp_desired" "$actual_path"
    return 0
  fi

  begin_marker="$(target_begin_marker_for_id "$id")"
  end_marker="$(target_end_marker_for_id "$id")"

  if [[ $id == "zsh-zdotdir" || $id == "bash-rc" || $id == "fish-config" ]]; then
    if [[ -L $actual_path ]]; then
      link_target="$(readlink "$actual_path" || true)"
      if [[ $link_target == /nix/store/* ]]; then
        write_fresh_block_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
        return $?
      fi
    fi

    write_entrypoint_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
    return $?
  fi

  write_block_to_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
}

ensure_zshrc_compat_link() {
  local zshrc="$HOME/.zshrc"
  local zdotdir_zshrc="$HOME/.nix/.zshrc"
  local desired_rel=".nix/.zshrc"
  local desired_abs="$zdotdir_zshrc"
  local link_target

  if [[ ! -e $zdotdir_zshrc && ! -L $zdotdir_zshrc ]]; then
    return 0
  fi

  if [[ -L $zshrc ]]; then
    link_target="$(readlink "$zshrc" || true)"
    if [[ $link_target == "$desired_rel" || $link_target == "$desired_abs" ]]; then
      return 0
    fi

    rm -f "$zshrc"
    if ln -s "$desired_rel" "$zshrc"; then
      log "updated ~/.zshrc compat symlink -> $desired_rel"
      return 0
    fi
    log "failed to update ~/.zshrc compat symlink"
    return 1
  fi

  if [[ -e $zshrc ]]; then
    log "skipped ~/.zshrc compat link: existing file is not a symlink"
    return 0
  fi

  if ln -s "$desired_rel" "$zshrc"; then
    log "created ~/.zshrc compat symlink -> $desired_rel"
    return 0
  fi

  log "failed to create ~/.zshrc compat symlink"
  return 1
}

sync_adapter_list_items() {
  local id desired_path actual_path

  while IFS= read -r id; do
    [[ -z $id ]] && continue
    desired_path="$(target_desired_path_for_id "$id")"
    actual_path="$(target_actual_path_for_id "$id")"
    printf '%s|%s|%s\n' "$id" "$desired_path" "$actual_path"
  done < <(list_target_ids)
}

sync_adapter_is_selected() {
  local id="$1"
  target_selected "$id"
}

sync_adapter_state_key() {
  local id="$1"
  printf '%s\n' "$id"
}

sync_adapter_extract_desired() {
  local id="$1"
  local output_file="$2"
  extract_desired_content_for_target "$id" "$output_file"
}

sync_adapter_extract_actual() {
  local id="$1"
  local output_file="$2"
  extract_actual_content_for_target "$id" "$output_file"
}

sync_adapter_write_desired_to_actual() {
  local id="$1"
  write_target_from_desired "$id"
}

sync_adapter_export_actual() {
  local id="$1"
  local destination="$2"
  export_actual_to_path "$id" "$destination"
}

sync_adapter_stage_fallback_basename() {
  local id="$1"
  printf '%s.block\n' "$id"
}

sync_adapter_print_details() {
  local id="$1"
  local _status="$2"
  local _desired_hash="$3"
  local _actual_hash="$4"
  local _last_hash="$5"
  local desired_meta="$6"
  local actual_meta="$7"
  print_target_details "$id" "$desired_meta" "$actual_meta"
}

sync_adapter_print_diff() {
  local id="$1"
  print_target_diff "$id"
}

sync_adapter_log_status() {
  local id="$1"
  local status="$2"
  local _desired_meta="$3"
  local actual_meta="$4"
  local last_hash="$5"

  case "$status" in
  safe-update)
    log "safe update pending: $id"
    log "  desired changed; current still matches lastApplied, apply can overwrite safely"
    ;;
  in-sync-untracked)
    log "in sync but no lastApplied state: $id"
    ;;
  state-stale)
    log "state stale (desired==actual, lastApplied is old): $id"
    ;;
  missing)
    log "missing managed content in local target: $id ($actual_meta)"
    ;;
  drift-untracked | drift-missing | drift-external | conflict)
    log "drift detected: $id"
    [[ -n $last_hash ]] && log "  lastApplied: $last_hash"
    case "$status" in
    drift-untracked)
      log "  reason: managed content exists without lastApplied and differs from desired"
      ;;
    drift-missing)
      log "  reason: managed content missing locally but lastApplied exists"
      ;;
    drift-external)
      log "  reason: local managed content changed outside dotfiles (desired==lastApplied, actual!=lastApplied)"
      ;;
    conflict)
      log "  reason: both desired and local changed from lastApplied"
      ;;
    esac
    ;;
  esac
}

sync_adapter_on_no_selection() {
  if [[ -n $target_filter ]]; then
    die "no target matched --target '$target_filter'"
  fi
  if [[ -n $shell_filter && $shell_filter != "all" ]]; then
    die "no target matched --shell '$shell_filter'"
  fi
  die "no shell targets selected"
}

sync_adapter_after_apply() {
  if target_selected "zsh-zdotdir"; then
    ensure_zshrc_compat_link
    return $?
  fi
  return 0
}

sync_adapter_print_summary() {
  if [[ $mode == "forget" ]]; then
    log "summary: forgotten=$sync_core_forgotten missing_state=$sync_core_missing_state"
    return 0
  fi

  log "summary: checked=$sync_core_checked in_sync=$sync_core_in_sync pending=$sync_core_pending state_stale=$sync_core_state_stale drift=$sync_core_drift conflicts=$sync_core_conflicts drift_missing=$sync_core_drift_missing missing=$sync_core_missing untracked=$sync_core_untracked applied=$sync_core_applied staged=$sync_core_staged adopted=$sync_core_adopted refused=$sync_core_refused unresolved=$sync_core_unresolved invalid=$sync_core_invalid errors=$sync_core_errors"
  log "managed dir: $managed_dir"
  log "state dir: $state_dir"
  [[ -n ${sync_core_resolved_output_dir:-} ]] && log "staging dir: $sync_core_resolved_output_dir"
}

sync_core_mode="$mode"
sync_core_details="$details"
sync_core_show_diff="$show_diff"
sync_core_in_place="$in_place"
sync_core_force="$force"
sync_core_output_dir="$output_dir"
sync_core_root="$ROOT"
sync_core_state_dir="$state_dir"
sync_core_staging_subdir="shell-adopt"
sync_core_invalid_desired_status="invalid-desired"
sync_core_invalid_actual_status="actual-invalid"
sync_core_error_status="error"
sync_core_invalid_seed=0
sync_core_forget_invalid_seed=0

if sync_core_run; then
  exit 0
fi

exit 1
