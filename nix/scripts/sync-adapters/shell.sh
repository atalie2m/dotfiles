#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="sync-shell"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/../load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- sync shell --check [--details] [--diff] [--group <zsh|bash|all>] [--item <id>] [--managed-dir <path>]
  nix run .#dotfiles -- sync shell --apply [--details] [--diff] [--group <zsh|bash|all>] [--item <id>] [--managed-dir <path>]

Description:
  Keep writable shell entrypoints aligned with repo-managed blocks/files.
  - zsh-zdotdir: managed block in ~/.nix/.zshrc
  - bash-rc: managed block in ~/.bashrc

Options:
  --check              Report in-sync / needs-apply / missing / invalid (default mode)
  --apply              Repair writable entrypoints and update managed content
  --details            Print concise per-target details
  --diff               Print unified diff for targets that need apply
  --group <name>       Filter targets by shell group (repeatable, default: all)
  --item <id>          Restrict to one target id
  --managed-dir <path> Desired managed content directory (default: <repo>/surfaces/shell/desired)
  --help               Show this help
USAGE
}

set_repo_root
managed_dir="$ROOT/surfaces/shell/desired"
mode="check"
mode_explicit=0
details=0
diff_output=0
group_filter=""
item_filter=""

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sync-shell.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

new_tmp_file() {
  mktemp "$tmp_dir/file.XXXXXX"
}

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

set_mode() {
  local next_mode="$1"

  if [[ $mode_explicit -eq 1 && $mode != "$next_mode" ]]; then
    die "choose only one of --check or --apply"
  fi

  mode="$next_mode"
  mode_explicit=1
}

removed_option_error() {
  local option_name="$1"
  die "$option_name is no longer supported for sync shell"
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
  --details)
    details=1
    shift
    ;;
  --diff)
    diff_output=1
    shift
    ;;
  --group)
    [[ $# -lt 2 ]] && die "missing value for --group"
    case "$2" in
    zsh | bash)
      append_shell_filter "$2"
      ;;
    all)
      group_filter="all"
      ;;
    *)
      die "invalid --group value: $2 (expected zsh, bash, all)"
      ;;
    esac
    shift 2
    ;;
  --item)
    [[ $# -lt 2 ]] && die "missing value for --item"
    item_filter="$2"
    shift 2
    ;;
  --managed-dir)
    [[ $# -lt 2 ]] && die "missing value for --managed-dir"
    managed_dir="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --adopt | --forget | --migrate | --state-dir | --force | --in-place | --output-dir)
    removed_option_error "$1"
    ;;
  *)
    die "unknown option for sync shell: $1"
    ;;
  esac
done

[[ -d $managed_dir ]] || die "managed dir not found: $managed_dir"

list_target_ids() {
  printf '%s\n' "zsh-zdotdir"
  printf '%s\n' "bash-rc"
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

canonicalize_text_to_file() {
  local source_file="$1"
  local output_file="$2"

  [[ -f $source_file ]] || return 1
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

write_managed_block_file() {
  local output_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"

  printf '%s\n' "$begin_marker" >"$output_file"
  /usr/bin/awk '{ sub(/\r$/, ""); print }' "$desired_file" >>"$output_file"
  printf '%s\n' "$end_marker" >>"$output_file"
}

write_entrypoint_file() {
  local target_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local tmp_out rc

  tmp_out="$(new_tmp_file)"

  if [[ -f $target_file ]]; then
    if replace_managed_block_in_file "$target_file" "$desired_file" "$begin_marker" "$end_marker" "$tmp_out"; then
      :
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then
        write_managed_block_file "$tmp_out" "$desired_file" "$begin_marker" "$end_marker"
        if [[ -s $target_file ]]; then
          printf '\n' >>"$tmp_out"
          /usr/bin/awk '{ sub(/\r$/, ""); print }' "$target_file" >>"$tmp_out"
        fi
      else
        rm -f "$tmp_out"
        return 1
      fi
    fi
  else
    write_managed_block_file "$tmp_out" "$desired_file" "$begin_marker" "$end_marker"
  fi

  mkdir -p "$(dirname "$target_file")"
  mv "$tmp_out" "$target_file"
}

write_whole_file_target() {
  local target_file="$1"
  local desired_file="$2"
  local tmp_out

  tmp_out="$(new_tmp_file)"
  canonicalize_text_to_file "$desired_file" "$tmp_out"
  mkdir -p "$(dirname "$target_file")"
  mv "$tmp_out" "$target_file"
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

classify_target() {
  local id="$1"
  local shell_name="$2"
  local target_type="$3"
  local actual_path="$4"
  local desired_path="$5"
  local begin_marker="$6"
  local end_marker="$7"
  local actual_kind actual_detail extract_rc

  TARGET_STATUS=""
  TARGET_REASON=""
  TARGET_ACTUAL_KIND=""
  TARGET_ACTUAL_DETAIL=""
  TARGET_SHAPE_NEEDS_REWRITE=0
  TARGET_DESIRED_TMP="$(new_tmp_file)"
  TARGET_ACTUAL_TMP="$(new_tmp_file)"

  canonicalize_text_to_file "$desired_path" "$TARGET_DESIRED_TMP" || die "desired file not found: $desired_path"

  IFS='|' read -r actual_kind actual_detail <<<"$(path_shape_for_target "$actual_path")"
  TARGET_ACTUAL_KIND="$actual_kind"
  TARGET_ACTUAL_DETAIL="$actual_detail"

  case "$target_type" in
  file)
    case "$actual_kind" in
    missing | symlink-broken)
      : >"$TARGET_ACTUAL_TMP"
      TARGET_STATUS="missing"
      TARGET_REASON="target is missing"
      return 0
      ;;
    directory | special | symlink-directory | symlink-special)
      TARGET_STATUS="invalid"
      TARGET_REASON="target is not a regular file"
      return 0
      ;;
    regular | symlink-regular | symlink-store)
      if canonicalize_text_to_file "$actual_path" "$TARGET_ACTUAL_TMP"; then
        if cmp -s "$TARGET_DESIRED_TMP" "$TARGET_ACTUAL_TMP"; then
          TARGET_STATUS="in-sync"
          TARGET_REASON="whole file matches desired"
        else
          TARGET_STATUS="needs-apply"
          TARGET_REASON="whole file differs from desired"
        fi
      else
        : >"$TARGET_ACTUAL_TMP"
        TARGET_STATUS="missing"
        TARGET_REASON="target contents are unreadable"
      fi
      return 0
      ;;
    *)
      die "unhandled file target shape '$actual_kind' for $id"
      ;;
    esac
    ;;
  block)
    case "$actual_kind" in
    missing)
      : >"$TARGET_ACTUAL_TMP"
      TARGET_STATUS="missing"
      TARGET_REASON="target is missing"
      return 0
      ;;
    directory | special | symlink-directory | symlink-special)
      TARGET_STATUS="invalid"
      TARGET_REASON="target is not a regular file"
      return 0
      ;;
    symlink-broken)
      TARGET_STATUS="invalid"
      TARGET_REASON="non-store symlink does not resolve to a regular file"
      return 0
      ;;
    symlink-store)
      TARGET_SHAPE_NEEDS_REWRITE=1
      ;;
    symlink-regular)
      TARGET_SHAPE_NEEDS_REWRITE=1
      ;;
    regular) ;;
    *)
      die "unhandled block target shape '$actual_kind' for $id"
      ;;
    esac

    if extract_managed_block "$actual_path" "$begin_marker" "$end_marker" "$TARGET_ACTUAL_TMP"; then
      if [[ $TARGET_SHAPE_NEEDS_REWRITE -eq 1 ]]; then
        TARGET_STATUS="needs-apply"
        TARGET_REASON="target should be materialized as a writable regular file"
      elif cmp -s "$TARGET_DESIRED_TMP" "$TARGET_ACTUAL_TMP"; then
        TARGET_STATUS="in-sync"
        TARGET_REASON="managed block matches desired"
      else
        TARGET_STATUS="needs-apply"
        TARGET_REASON="managed block differs from desired"
      fi
      return 0
    else
      extract_rc=$?
    fi

    case "$extract_rc" in
    2)
      : >"$TARGET_ACTUAL_TMP"
      if [[ $TARGET_SHAPE_NEEDS_REWRITE -eq 1 ]]; then
        TARGET_STATUS="needs-apply"
        TARGET_REASON="target should be materialized as a writable regular file"
      else
        TARGET_STATUS="needs-apply"
        TARGET_REASON="managed block is missing"
      fi
      ;;
    3)
      TARGET_STATUS="invalid"
      TARGET_REASON="managed block markers are duplicated or malformed"
      ;;
    *)
      TARGET_STATUS="invalid"
      TARGET_REASON="failed to inspect managed block"
      ;;
    esac
    return 0
    ;;
  *)
    die "unknown target type for $id: $target_type"
    ;;
  esac
}

print_target_details() {
  local id="$1"
  local shell_name="$2"
  local target_type="$3"
  local actual_path="$4"
  local desired_path="$5"

  log "details: $id"
  log "  shell: $shell_name"
  log "  type: $target_type"
  log "  status: $TARGET_STATUS"
  log "  target: $actual_path"
  log "  desired: $desired_path"
  if [[ -n $TARGET_ACTUAL_DETAIL ]]; then
    log "  actual-type: $TARGET_ACTUAL_KIND ($TARGET_ACTUAL_DETAIL)"
  else
    log "  actual-type: $TARGET_ACTUAL_KIND"
  fi
  log "  reason: $TARGET_REASON"
}

print_target_diff() {
  local id="$1"

  log "diff: $id"
  if [[ $TARGET_SHAPE_NEEDS_REWRITE -eq 1 ]] && cmp -s "$TARGET_DESIRED_TMP" "$TARGET_ACTUAL_TMP"; then
    log "  note: content matches desired, but target must be rewritten as a writable regular file"
    return 0
  fi
  /usr/bin/diff -u "$TARGET_DESIRED_TMP" "$TARGET_ACTUAL_TMP" || true
}

apply_target() {
  local id="$1"
  local target_type="$2"
  local actual_path="$3"
  local desired_path="$4"
  local begin_marker="$5"
  local end_marker="$6"

  case "$target_type" in
  block)
    case "$TARGET_ACTUAL_KIND" in
    missing | regular | symlink-store | symlink-regular)
      write_entrypoint_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
      return 0
      ;;
    *)
      return 1
      ;;
    esac
    ;;
  file)
    case "$TARGET_ACTUAL_KIND" in
    missing | regular | symlink-store | symlink-regular | symlink-broken)
      write_whole_file_target "$actual_path" "$desired_path"
      return 0
      ;;
    *)
      return 1
      ;;
    esac
    ;;
  esac

  return 1
}

selected_count=0
checked=0
in_sync=0
needs_apply=0
missing=0
invalid=0
applied=0
errors=0

while IFS= read -r id; do
  [[ -z $id ]] && continue

  if ! meta="$(target_meta_for_id "$id")"; then
    die "unknown shell target id: $id"
  fi

  IFS='|' read -r shell_name target_type actual_path desired_path begin_marker end_marker <<<"$meta"

  if ! target_selected "$id" "$shell_name"; then
    continue
  fi

  selected_count=$((selected_count + 1))
  checked=$((checked + 1))

  classify_target "$id" "$shell_name" "$target_type" "$actual_path" "$desired_path" "$begin_marker" "$end_marker"

  case "$TARGET_STATUS" in
  in-sync)
    in_sync=$((in_sync + 1))
    ;;
  needs-apply)
    needs_apply=$((needs_apply + 1))
    ;;
  missing)
    missing=$((missing + 1))
    ;;
  invalid)
    invalid=$((invalid + 1))
    ;;
  *)
    errors=$((errors + 1))
    log "unexpected status for '$id': $TARGET_STATUS"
    ;;
  esac

  if [[ $details -eq 1 ]]; then
    print_target_details "$id" "$shell_name" "$target_type" "$actual_path" "$desired_path"
  fi

  if [[ $diff_output -eq 1 && $TARGET_STATUS == "needs-apply" ]]; then
    print_target_diff "$id"
  fi

  if [[ $mode == "apply" ]]; then
    case "$TARGET_STATUS" in
    in-sync) ;;
    missing | needs-apply)
      if apply_target "$id" "$target_type" "$actual_path" "$desired_path" "$begin_marker" "$end_marker"; then
        classify_target "$id" "$shell_name" "$target_type" "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
        if [[ $TARGET_STATUS == "in-sync" ]]; then
          applied=$((applied + 1))
        else
          errors=$((errors + 1))
          log "apply failed to converge '$id': status=$TARGET_STATUS"
        fi
      else
        errors=$((errors + 1))
        log "apply failed for '$id': $TARGET_REASON"
      fi
      ;;
    invalid)
      errors=$((errors + 1))
      log "apply refused for '$id': $TARGET_REASON"
      ;;
    esac
  fi
done < <(list_target_ids)

if [[ $selected_count -eq 0 ]]; then
  if [[ -n $item_filter ]]; then
    die "no item matched --item '$item_filter'"
  fi
  if [[ -n $group_filter && $group_filter != "all" ]]; then
    die "no item matched --group '$group_filter'"
  fi
  die "no shell targets selected"
fi

log "summary: checked=$checked in_sync=$in_sync needs_apply=$needs_apply missing=$missing invalid=$invalid applied=$applied errors=$errors"

if [[ $mode == "apply" ]]; then
  [[ $errors -eq 0 ]]
  exit $?
fi

if [[ $needs_apply -eq 0 && $missing -eq 0 && $invalid -eq 0 && $errors -eq 0 ]]; then
  exit 0
fi

exit 1
