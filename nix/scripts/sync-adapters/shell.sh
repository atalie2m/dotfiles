#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="sync-shell"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/../load-lib.sh"
# shellcheck source=sync-core.sh
source_dotfiles_script "sync-core.sh"
# shellcheck disable=SC2317

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- sync shell --check [--details] [--diff] [--group <zsh|bash|fish|all>] [--item <id>] [--managed-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- sync shell --apply [--details] [--diff] [--group <zsh|bash|fish|all>] [--item <id>] [--managed-dir <path>] [--state-dir <path>] [--force]
  nix run .#dotfiles -- sync shell --adopt [--details] [--diff] [--group <zsh|bash|fish|all>] [--item <id>] [--managed-dir <path>] [--state-dir <path>] [--in-place] [--force] [--output-dir <path>]
  nix run .#dotfiles -- sync shell --migrate [--group <zsh|bash|fish|all>] [--item <id>] [--managed-dir <path>]
  nix run .#dotfiles -- sync shell --forget [--group <zsh|bash|fish|all>] [--item <id>] [--state-dir <path>]

Description:
  Manage shell config with lastApplied 3-way status.
  - zsh-zdotdir: managed block in ~/.nix/.zshrc (runtime entrypoint)
  - bash-rc: managed block in ~/.bashrc (runtime entrypoint)
  - fish-config: managed block in ~/.config/fish/config.fish (runtime entrypoint)
  - fish-core: whole file at ~/.config/fish/conf.d/00-dotfiles.fish

Options:
  --check              Detect drift/missing/invalid (default mode)
  --apply              Apply desired managed content to local targets
  --adopt              Export current local managed content for drifted targets
  --migrate            Convert legacy/invalid entrypoint targets to writable expected shape
  --forget             Remove last-applied hash state
  --group <name>       Filter targets by shell group (repeatable, default: all)
  --item <id>          Filter one target id (zsh-zdotdir, bash-rc, fish-config, fish-core)
  --details            Print concise per-target details
  --diff               Print unified diff (desired vs current)
  --managed-dir <path> Desired managed content directory (default: <repo>/surfaces/shell/desired)
  --state-dir <path>   Last-applied hash directory (default: $XDG_STATE_HOME/dotfiles/sync/shell/blocks)
  --in-place           With --adopt, overwrite desired files in place
  --force              With --apply, allow overwrite on drift/conflict; with --adopt --in-place, allow conflict overwrite
  --output-dir <path>  With --adopt (staging mode), directory for exported managed content
USAGE
}

group_filter=""
default_managed_dir=1
migrate_requested=0

set_repo_root
sync_core_init_cli_defaults
sync_core_root="$ROOT"
managed_dir="$ROOT/surfaces/shell/desired"
sync_core_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/sync/shell/blocks"

append_shell_filter() {
  local shell_name="$1"

  if [[ $group_filter == "all" ]]; then
    return 0
  fi

  if [[ -z $group_filter ]]; then
    group_filter="$shell_name"
    return 0
  fi

  case ",$group_filter," in
  *",$shell_name,"*) ;;
  *)
    group_filter="$group_filter,$shell_name"
    ;;
  esac
}

sync_cli_parse_script_option() {
  case "$1" in
  --group)
    [[ $# -lt 2 ]] && die "missing value for --group"
    case "$2" in
    zsh | bash | fish)
      append_shell_filter "$2"
      ;;
    all)
      group_filter="all"
      ;;
    *)
      die "invalid --group value: $2 (expected zsh, bash, fish, all)"
      ;;
    esac
    sync_core_cli_consumed=2
    return 0
    ;;
  --migrate)
    migrate_requested=1
    sync_core_cli_consumed=1
    return 0
    ;;
  --managed-dir)
    [[ $# -lt 2 ]] && die "missing value for --managed-dir"
    managed_dir="$2"
    default_managed_dir=0
    sync_core_cli_consumed=2
    return 0
    ;;
  esac

  return 1
}

sync_core_parse_cli_args 1 "$@"

if [[ $migrate_requested -eq 1 ]]; then
  if [[ $sync_core_mode != "check" ]]; then
    die "--migrate cannot be combined with --check/--apply/--adopt/--forget"
  fi
  sync_core_mode="migrate"
fi

managed_dir="$(sync_core_resolve_surface_dir "surfaces/shell/desired" "$managed_dir" "$default_managed_dir")"
ROOT="$sync_core_root"

if [[ $sync_core_mode != "migrate" ]]; then
  sync_core_validate_adopt_flags "$sync_core_mode" "$sync_core_in_place" "$sync_core_output_dir"
  sync_core_validate_force_usage "$sync_core_mode" "$sync_core_in_place" "$sync_core_force" 1 "--force is only valid with --apply or --adopt --in-place"
else
  if [[ $sync_core_in_place -eq 1 || -n $sync_core_output_dir || $sync_core_force -eq 1 ]]; then
    die "--in-place/--output-dir/--force are not valid with --migrate"
  fi
fi

if [[ $sync_core_mode != "forget" && ! -d $managed_dir ]]; then
  die "managed dir not found: $managed_dir"
fi

list_target_ids() {
  printf '%s\n' "zsh-zdotdir"
  printf '%s\n' "bash-rc"
  printf '%s\n' "fish-config"
  printf '%s\n' "fish-core"
}

target_meta_for_id() {
  case "$1" in
  zsh-zdotdir)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "zsh" "block" "$HOME/.nix/.zshrc" "$managed_dir/zdotdir.zshrc.block.sh" \
      "# >>> dotfiles-managed:zdotdir.zshrc >>>" "# <<< dotfiles-managed:zdotdir.zshrc <<<"
    ;;
  bash-rc)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "bash" "block" "$HOME/.bashrc" "$managed_dir/bashrc.entrypoint.block.sh" \
      "# >>> dotfiles-managed:bashrc >>>" "# <<< dotfiles-managed:bashrc <<<"
    ;;
  fish-config)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "fish" "block" "$HOME/.config/fish/config.fish" "$managed_dir/fish.config.block.fish" \
      "# >>> dotfiles-managed:fish.config >>>" "# <<< dotfiles-managed:fish.config <<<"
    ;;
  fish-core)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "fish" "file" "$HOME/.config/fish/conf.d/00-dotfiles.fish" "$managed_dir/00-dotfiles.fish" "" ""
    ;;
  *)
    return 1
    ;;
  esac
}

target_read_meta() {
  local id="$1"
  local shell_name type_name actual_path desired_path begin_marker end_marker

  IFS='|' read -r shell_name type_name actual_path desired_path begin_marker end_marker \
    <<<"$(target_meta_for_id "$id")" || return 1

  printf '%s|%s|%s|%s|%s|%s\n' "$shell_name" "$type_name" "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
}

target_shell_for_id() {
  local _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker
  IFS='|' read -r _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker \
    <<<"$(target_read_meta "$1")" || return 1
  printf '%s\n' "$_shell_name"
}

target_type_for_id() {
  local _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker
  IFS='|' read -r _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker \
    <<<"$(target_read_meta "$1")" || return 1
  printf '%s\n' "$_type_name"
}

target_actual_path_for_id() {
  local _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker
  IFS='|' read -r _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker \
    <<<"$(target_read_meta "$1")" || return 1
  printf '%s\n' "$_actual_path"
}

target_desired_path_for_id() {
  local _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker
  IFS='|' read -r _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker \
    <<<"$(target_read_meta "$1")" || return 1
  printf '%s\n' "$_desired_path"
}

target_begin_marker_for_id() {
  local _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker
  IFS='|' read -r _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker \
    <<<"$(target_read_meta "$1")" || return 1
  printf '%s\n' "$_begin_marker"
}

target_end_marker_for_id() {
  local _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker
  IFS='|' read -r _shell_name _type_name _actual_path _desired_path _begin_marker _end_marker \
    <<<"$(target_read_meta "$1")" || return 1
  printf '%s\n' "$_end_marker"
}

target_selected() {
  local id="$1"
  local shell_name

  if [[ -z $group_filter || $group_filter == "all" ]]; then
    return 0
  fi

  shell_name="$(target_shell_for_id "$id" || true)"
  if [[ -z $shell_name ]]; then
    return 1
  fi

  case ",$group_filter," in
  *",$shell_name,"*) return 0 ;;
  *) return 1 ;;
  esac
}

migrate_target_selected() {
  local id="$1"
  sync_core_is_selected_default "$id" || return 1
  target_selected "$id"
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
  local tmp_out tmp_replaced rc link_target preserve_existing attempt_replace

  attempt_replace=0
  if [[ -f $target_file ]]; then
    attempt_replace=1
  elif [[ -L $target_file ]]; then
    link_target="$(readlink "$target_file" || true)"
    if [[ $link_target != /nix/store/* && -f $target_file ]]; then
      attempt_replace=1
    fi
  fi

  if [[ $attempt_replace -eq 1 ]]; then
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

target_is_entrypoint_id() {
  case "$1" in
  zsh-zdotdir | bash-rc | fish-config) return 0 ;;
  *) return 1 ;;
  esac
}

apply_shape_error() {
  local id="$1"
  local reason="$2"
  log "apply refused for '$id': $reason"
  log "  run: nix run .#dotfiles -- sync shell --migrate (use the same --item/--group filters)"
}

validate_entrypoint_shape_for_apply() {
  local id="$1"
  local actual_path="$2"

  if [[ -L $actual_path ]]; then
    apply_shape_error "$id" "target is a symlink: $actual_path"
    return 1
  fi

  if [[ -e $actual_path && ! -f $actual_path ]]; then
    apply_shape_error "$id" "target is not a regular file: $actual_path"
    return 1
  fi

  if [[ ! -e $actual_path ]]; then
    apply_shape_error "$id" "target is missing: $actual_path"
    return 1
  fi

  return 0
}

write_target_from_desired() {
  local id="$1"
  local target_type desired_path actual_path begin_marker end_marker tmp_desired

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

  if target_is_entrypoint_id "$id"; then
    if ! validate_entrypoint_shape_for_apply "$id" "$actual_path"; then
      return 1
    fi
    write_entrypoint_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
    return $?
  fi

  write_block_to_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
}

migrate_entrypoint_target() {
  local id="$1"
  local desired_path actual_path begin_marker end_marker

  desired_path="$(target_desired_path_for_id "$id")"
  actual_path="$(target_actual_path_for_id "$id")"
  begin_marker="$(target_begin_marker_for_id "$id")"
  end_marker="$(target_end_marker_for_id "$id")"

  if [[ -e $actual_path && ! -f $actual_path && ! -L $actual_path ]]; then
    log "migrate refused for '$id': target is not a regular file or symlink: $actual_path"
    return 1
  fi

  if [[ ! -e $actual_path && ! -L $actual_path ]]; then
    write_fresh_block_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
    log "migrated missing entrypoint: $id"
    return 0
  fi

  if write_entrypoint_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"; then
    log "migrated entrypoint target: $id"
    return 0
  fi

  log "failed to migrate entrypoint target: $id"
  return 1
}

run_migrate_mode() {
  local id selected_count migrated_count errors
  selected_count=0
  migrated_count=0
  errors=0

  while IFS= read -r id; do
    [[ -z $id ]] && continue
    if ! migrate_target_selected "$id"; then
      continue
    fi

    selected_count=$((selected_count + 1))

    if target_is_entrypoint_id "$id"; then
      if migrate_entrypoint_target "$id"; then
        migrated_count=$((migrated_count + 1))
      else
        errors=$((errors + 1))
      fi
      continue
    fi

    if [[ $id == "fish-core" ]]; then
      if [[ -e "$(target_actual_path_for_id "$id")" && ! -f "$(target_actual_path_for_id "$id")" ]]; then
        log "migrate refused for '$id': target is not a regular file"
        errors=$((errors + 1))
      elif [[ ! -f "$(target_actual_path_for_id "$id")" ]]; then
        if write_target_from_desired "$id"; then
          log "migrated missing target: $id"
          migrated_count=$((migrated_count + 1))
        else
          log "failed to migrate target: $id"
          errors=$((errors + 1))
        fi
      fi
    fi
  done < <(list_target_ids)

  if [[ $selected_count -eq 0 ]]; then
    sync_adapter_on_no_selection
  fi

  log "summary: migrated=$migrated_count selected=$selected_count errors=$errors"
  [[ $errors -eq 0 ]]
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

sync_adapter_on_no_selection() {
  if [[ -n ${sync_core_item_filter:-} ]]; then
    die "no item matched --item '$sync_core_item_filter'"
  fi
  if [[ -n $group_filter && $group_filter != "all" ]]; then
    die "no item matched --group '$group_filter'"
  fi
  die "no shell targets selected"
}

sync_adapter_print_summary_extra() {
  log "managed dir: $managed_dir"
}

if [[ $sync_core_mode == "migrate" ]]; then
  if run_migrate_mode; then
    exit 0
  fi
  exit 1
fi

sync_core_root="$ROOT"
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
