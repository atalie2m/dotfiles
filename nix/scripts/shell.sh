#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="shell"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

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
  - zsh-local: whole file at ~/.zshrc.local (local hooks)
  - bash: managed block in ~/.bashrc.local
  - fish: whole file at ~/.config/fish/conf.d/00-dotfiles.fish

Options:
  --check              Detect drift/missing/invalid (default mode)
  --apply              Apply desired managed content to local targets
  --adopt              Export current local managed content for drifted targets
  --forget             Remove last-applied hash state
  --shell <name>       Filter targets by shell (repeatable, default: all)
  --target <id>        Filter one target id (zsh-zdotdir, zsh-local, bash-local, fish-core)
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

resolve_repo_worktree_root() {
  local candidate=""

  if command -v git >/dev/null 2>&1; then
    candidate="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n $candidate && -f $candidate/flake.nix && -d $candidate/apps/shell/managed && -d $candidate/nix/scripts ]]; then
      cd "$candidate" && pwd
      return 0
    fi
  fi

  if [[ -f "$(pwd)/flake.nix" && -d "$(pwd)/apps/shell/managed" && -d "$(pwd)/nix/scripts" ]]; then
    pwd
    return 0
  fi

  return 1
}

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

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    mode="check"
    shift
    ;;
  --apply)
    mode="apply"
    shift
    ;;
  --adopt)
    mode="adopt"
    shift
    ;;
  --forget)
    mode="forget"
    shift
    ;;
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
    shift 2
    ;;
  --target)
    [[ $# -lt 2 ]] && die "missing value for --target"
    target_filter="$2"
    shift 2
    ;;
  --details)
    details=1
    shift
    ;;
  --diff)
    show_diff=1
    shift
    ;;
  --managed-dir)
    [[ $# -lt 2 ]] && die "missing value for --managed-dir"
    managed_dir="$2"
    default_managed_dir=0
    shift 2
    ;;
  --state-dir)
    [[ $# -lt 2 ]] && die "missing value for --state-dir"
    state_dir="$2"
    shift 2
    ;;
  --in-place)
    in_place=1
    shift
    ;;
  --force)
    force=1
    shift
    ;;
  --output-dir)
    [[ $# -lt 2 ]] && die "missing value for --output-dir"
    output_dir="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    die "unknown option: $1"
    ;;
  *)
    die "unexpected argument: $1"
    ;;
  esac
done

if [[ $default_managed_dir -eq 1 ]]; then
  worktree_root="$(resolve_repo_worktree_root || true)"
  if [[ -n $worktree_root ]]; then
    ROOT="$worktree_root"
    managed_dir="$ROOT/apps/shell/managed"
  fi
fi

if [[ $mode != "adopt" && ($in_place -eq 1 || -n $output_dir) ]]; then
  die "--in-place/--output-dir are only valid with --adopt"
fi

if [[ $mode == "check" && $force -eq 1 ]]; then
  die "--force is only valid with --apply or --adopt --in-place"
fi

if [[ $mode == "adopt" && $in_place -eq 1 && -n $output_dir ]]; then
  die "--output-dir cannot be used with --adopt --in-place"
fi

if [[ $mode == "adopt" && $in_place -eq 0 && $force -eq 1 ]]; then
  die "--force is only valid with --adopt --in-place"
fi

if [[ $mode != "forget" && ! -d $managed_dir ]]; then
  die "managed dir not found: $managed_dir"
fi

list_target_ids() {
  printf '%s\n' "zsh-zdotdir"
  printf '%s\n' "zsh-local"
  printf '%s\n' "bash-local"
  printf '%s\n' "fish-core"
}

target_shell_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "zsh" ;;
  zsh-local) printf '%s\n' "zsh" ;;
  bash-local) printf '%s\n' "bash" ;;
  fish-core) printf '%s\n' "fish" ;;
  *)
    return 1
    ;;
  esac
}

target_type_for_id() {
  case "$1" in
  zsh-local | fish-core) printf '%s\n' "file" ;;
  zsh-zdotdir | bash-local) printf '%s\n' "block" ;;
  *)
    return 1
    ;;
  esac
}

target_actual_path_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "$HOME/.nix/.zshrc" ;;
  zsh-local) printf '%s\n' "$HOME/.zshrc.local" ;;
  bash-local) printf '%s\n' "$HOME/.bashrc.local" ;;
  fish-core) printf '%s\n' "$HOME/.config/fish/conf.d/00-dotfiles.fish" ;;
  *)
    return 1
    ;;
  esac
}

target_desired_path_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "$managed_dir/zdotdir.zshrc.block.sh" ;;
  zsh-local) printf '%s\n' "$managed_dir/zshrc.local.sh" ;;
  bash-local) printf '%s\n' "$managed_dir/bashrc.local.block.sh" ;;
  fish-core) printf '%s\n' "$managed_dir/00-dotfiles.fish" ;;
  *)
    return 1
    ;;
  esac
}

target_begin_marker_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "# >>> dotfiles-managed:zdotdir.zshrc >>>" ;;
  zsh-local) printf '%s\n' "" ;;
  bash-local) printf '%s\n' "# >>> dotfiles-managed:bashrc.local >>>" ;;
  fish-core) printf '%s\n' "" ;;
  *)
    return 1
    ;;
  esac
}

target_end_marker_for_id() {
  case "$1" in
  zsh-zdotdir) printf '%s\n' "# <<< dotfiles-managed:zdotdir.zshrc <<<" ;;
  zsh-local) printf '%s\n' "" ;;
  bash-local) printf '%s\n' "# <<< dotfiles-managed:bashrc.local <<<" ;;
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

is_sha256_hash() {
  local value="$1"
  [[ $value =~ ^[0-9a-fA-F]{64}$ ]]
}

state_file_for_target() {
  local id="$1"
  printf '%s/%s.sha256\n' "$state_dir" "$id"
}

read_last_applied_hash() {
  local id="$1"
  local state_file

  state_file="$(state_file_for_target "$id")"
  if [[ -f $state_file ]]; then
    head -n 1 "$state_file" | tr -d '[:space:]'
  fi
}

write_last_applied_hash() {
  local id="$1"
  local hash="$2"
  local state_file

  state_file="$(state_file_for_target "$id")"
  mkdir -p "$state_dir"
  printf '%s\n' "$hash" >"$state_file"
}

forget_last_applied_hash() {
  local id="$1"
  local state_file

  state_file="$(state_file_for_target "$id")"
  if [[ -f $state_file ]]; then
    rm -f "$state_file"
    return 0
  fi
  return 1
}

canonicalize_text_to_file() {
  local source_file="$1"
  local output_file="$2"
  /usr/bin/awk '{ sub(/\r$/, ""); print }' "$source_file" >"$output_file"
}

canonical_hash_from_file() {
  local file="$1"
  local tmp

  tmp="$(mktemp)"
  canonicalize_text_to_file "$file" "$tmp"
  /usr/bin/shasum -a 256 "$tmp" | /usr/bin/awk '{print $1}'
  rm -f "$tmp"
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
    rc=$?
    case "$rc" in
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
    rc=$?
    rm -f "$tmp_block"
    return "$rc"
  fi
}

determine_target_status() {
  local id="$1"
  local desired_path actual_path desired_tmp actual_tmp desired_hash actual_hash last_hash status rc

  desired_path="$(target_desired_path_for_id "$id")"
  actual_path="$(target_actual_path_for_id "$id")"
  desired_tmp="$(mktemp)"
  actual_tmp="$(mktemp)"
  desired_hash=""
  actual_hash=""
  last_hash="$(read_last_applied_hash "$id")"

  if ! extract_desired_content_for_target "$id" "$desired_tmp"; then
    rm -f "$desired_tmp" "$actual_tmp"
    printf 'invalid-desired|%s|||%s|%s|%s\n' "$id" "$last_hash" "$desired_path" "$actual_path"
    return 0
  fi

  desired_hash="$(canonical_hash_from_file "$desired_tmp" || true)"
  if [[ -z $desired_hash ]]; then
    rm -f "$desired_tmp" "$actual_tmp"
    printf 'invalid-desired|%s|||%s|%s|%s\n' "$id" "$last_hash" "$desired_path" "$actual_path"
    return 0
  fi

  if extract_actual_content_for_target "$id" "$actual_tmp"; then
    actual_hash="$(canonical_hash_from_file "$actual_tmp" || true)"
    if [[ -z $actual_hash ]]; then
      rm -f "$desired_tmp" "$actual_tmp"
      printf 'error|%s|%s||%s|%s|%s\n' "$id" "$desired_hash" "$last_hash" "$desired_path" "$actual_path"
      return 0
    fi
  else
    rc=$?
    case "$rc" in
    2)
      actual_hash=""
      ;;
    3)
      rm -f "$desired_tmp" "$actual_tmp"
      printf 'actual-invalid|%s|%s||%s|%s|%s\n' "$id" "$desired_hash" "$last_hash" "$desired_path" "$actual_path"
      return 0
      ;;
    *)
      rm -f "$desired_tmp" "$actual_tmp"
      printf 'error|%s|%s||%s|%s|%s\n' "$id" "$desired_hash" "$last_hash" "$desired_path" "$actual_path"
      return 0
      ;;
    esac
  fi

  rm -f "$desired_tmp" "$actual_tmp"

  if [[ -n $last_hash ]] && ! is_sha256_hash "$last_hash"; then
    printf 'state-invalid|%s|%s|%s|%s|%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_path" "$actual_path"
    return 0
  fi

  if [[ -n $last_hash ]]; then
    if [[ -z $actual_hash ]]; then
      printf 'drift-missing|%s|%s||%s|%s|%s\n' "$id" "$desired_hash" "$last_hash" "$desired_path" "$actual_path"
      return 0
    fi

    if [[ $actual_hash == "$last_hash" ]]; then
      if [[ $actual_hash == "$desired_hash" ]]; then
        printf 'in-sync|%s|%s|%s|%s|%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_path" "$actual_path"
      else
        printf 'safe-update|%s|%s|%s|%s|%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_path" "$actual_path"
      fi
      return 0
    fi

    if [[ $actual_hash == "$desired_hash" ]]; then
      printf 'state-stale|%s|%s|%s|%s|%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_path" "$actual_path"
      return 0
    fi

    if [[ $desired_hash == "$last_hash" ]]; then
      printf 'drift-external|%s|%s|%s|%s|%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_path" "$actual_path"
      return 0
    fi

    printf 'conflict|%s|%s|%s|%s|%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_path" "$actual_path"
    return 0
  fi

  if [[ -z $actual_hash ]]; then
    printf 'missing|%s|%s|||%s|%s\n' "$id" "$desired_hash" "$desired_path" "$actual_path"
    return 0
  fi

  if [[ $actual_hash == "$desired_hash" ]]; then
    printf 'in-sync-untracked|%s|%s|%s||%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$desired_path" "$actual_path"
  else
    printf 'drift-untracked|%s|%s|%s||%s|%s\n' "$id" "$desired_hash" "$actual_hash" "$desired_path" "$actual_path"
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

write_zdotdir_entrypoint_file() {
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

  if [[ $id == "zsh-zdotdir" ]]; then
    if [[ -L $actual_path ]]; then
      link_target="$(readlink "$actual_path" || true)"
      if [[ $link_target == /nix/store/* ]]; then
        write_fresh_block_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
        return $?
      fi
    fi

    write_zdotdir_entrypoint_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
    return $?
  fi

  write_block_to_file "$actual_path" "$desired_path" "$begin_marker" "$end_marker"
}

compute_actual_hash_for_target() {
  local id="$1"
  local tmp_actual hash

  tmp_actual="$(mktemp)"
  if ! extract_actual_content_for_target "$id" "$tmp_actual"; then
    rm -f "$tmp_actual"
    return 1
  fi

  hash="$(canonical_hash_from_file "$tmp_actual" || true)"
  rm -f "$tmp_actual"
  [[ -n $hash ]] || return 1
  printf '%s\n' "$hash"
}

ensure_zshrc_compat_link() {
  local zshrc="$HOME/.zshrc"
  local zdotdir_zshrc="$HOME/.nix/.zshrc"
  local zshrc_local="$HOME/.zshrc.local"
  local desired_rel=""
  local desired_abs=""
  local link_target

  if [[ -e $zdotdir_zshrc || -L $zdotdir_zshrc ]]; then
    desired_rel=".nix/.zshrc"
    desired_abs="$zdotdir_zshrc"
  elif [[ -e $zshrc_local || -L $zshrc_local ]]; then
    desired_rel=".zshrc.local"
    desired_abs="$zshrc_local"
  else
    return 0
  fi

  if [[ -L $zshrc ]]; then
    link_target="$(readlink "$zshrc" || true)"
    if [[ $link_target == "$desired_rel" || $link_target == "$desired_abs" ]]; then
      return 0
    fi

    case "$link_target" in
    ".zshrc.local" | "$zshrc_local" | ".nix/.zshrc" | "$zdotdir_zshrc")
      rm -f "$zshrc"
      if ln -s "$desired_rel" "$zshrc"; then
        log "updated ~/.zshrc compat symlink -> $desired_rel"
        return 0
      fi
      log "failed to update ~/.zshrc compat symlink"
      return 1
      ;;
    *)
      log "skipped ~/.zshrc compat link: existing symlink points to $link_target"
      return 0
      ;;
    esac
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

forget_mode() {
  local forgotten=0 missing_state=0 selected=0
  local id

  while IFS= read -r id; do
    [[ -z $id ]] && continue
    if ! target_selected "$id"; then
      continue
    fi

    selected=$((selected + 1))
    if forget_last_applied_hash "$id"; then
      forgotten=$((forgotten + 1))
      log "forgot lastApplied state: $id"
    else
      missing_state=$((missing_state + 1))
      log "no lastApplied state found: $id"
    fi
  done < <(list_target_ids)

  if [[ $selected -eq 0 ]]; then
    if [[ -n $target_filter ]]; then
      die "no target matched --target '$target_filter'"
    fi
    if [[ -n $shell_filter && $shell_filter != "all" ]]; then
      die "no target matched --shell '$shell_filter'"
    fi
    die "no targets selected"
  fi

  log "summary: forgotten=$forgotten missing_state=$missing_state"
  exit 0
}

if [[ $mode == "forget" ]]; then
  forget_mode
fi

checked=0
selected=0
in_sync=0
pending=0
state_stale=0
drift=0
drift_missing=0
conflicts=0
missing=0
untracked=0
invalid=0
errors=0
applied=0
staged=0
adopted=0
refused=0
adoptable_drift=0
unresolved=0

resolved_output_dir=""

while IFS= read -r id; do
  [[ -z $id ]] && continue

  if ! target_selected "$id"; then
    continue
  fi

  selected=$((selected + 1))
  checked=$((checked + 1))

  status_line="$(determine_target_status "$id")"
  IFS='|' read -r status _ desired_hash actual_hash last_hash desired_path actual_path <<<"$status_line"

  case "$status" in
  in-sync)
    in_sync=$((in_sync + 1))
    ;;
  safe-update)
    pending=$((pending + 1))
    log "safe update pending: $id"
    log "  desired changed; current still matches lastApplied, apply can overwrite safely"
    if [[ $mode == "apply" ]]; then
      if write_target_from_desired "$id"; then
        applied_hash="$(compute_actual_hash_for_target "$id" || true)"
        if [[ -z $applied_hash ]]; then
          log "failed to compute applied hash for '$id'"
          errors=$((errors + 1))
        elif ! write_last_applied_hash "$id" "$applied_hash"; then
          log "failed to write lastApplied state for '$id'"
          errors=$((errors + 1))
        else
          applied=$((applied + 1))
          log "applied managed content: $id"
        fi
      else
        log "failed to apply managed content: $id"
        errors=$((errors + 1))
      fi
    fi
    ;;
  in-sync-untracked)
    in_sync=$((in_sync + 1))
    untracked=$((untracked + 1))
    log "in sync but no lastApplied state: $id"
    if [[ $mode == "apply" ]]; then
      if [[ -n $actual_hash ]] && write_last_applied_hash "$id" "$actual_hash"; then
        log "wrote missing lastApplied state: $id"
      else
        log "failed to write missing lastApplied state: $id"
        errors=$((errors + 1))
      fi
    fi
    ;;
  state-stale)
    in_sync=$((in_sync + 1))
    state_stale=$((state_stale + 1))
    log "state stale (desired==actual, lastApplied is old): $id"
    if [[ $mode == "apply" ]]; then
      if [[ -n $actual_hash ]] && write_last_applied_hash "$id" "$actual_hash"; then
        log "refreshed lastApplied state: $id"
      else
        log "failed to refresh lastApplied state: $id"
        errors=$((errors + 1))
      fi
    fi
    ;;
  missing)
    missing=$((missing + 1))
    log "missing managed content in local target: $id ($actual_path)"
    if [[ $mode == "apply" ]]; then
      if write_target_from_desired "$id"; then
        applied_hash="$(compute_actual_hash_for_target "$id" || true)"
        if [[ -z $applied_hash ]]; then
          log "failed to compute applied hash for '$id'"
          errors=$((errors + 1))
        elif ! write_last_applied_hash "$id" "$applied_hash"; then
          log "failed to write lastApplied state for '$id'"
          errors=$((errors + 1))
        else
          applied=$((applied + 1))
          log "applied managed content: $id"
        fi
      else
        log "failed to apply managed content: $id"
        errors=$((errors + 1))
      fi
    fi
    ;;
  drift-untracked | drift-missing | drift-external | conflict)
    drift=$((drift + 1))
    [[ $status == "conflict" ]] && conflicts=$((conflicts + 1))
    [[ $status == "drift-missing" ]] && drift_missing=$((drift_missing + 1))

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

    if [[ $details -eq 1 ]]; then
      print_target_details "$id" "$desired_path" "$actual_path"
    fi

    if [[ $show_diff -eq 1 && $status != "drift-missing" ]]; then
      print_target_diff "$id" || true
    fi

    if [[ $status != "drift-missing" ]]; then
      adoptable_drift=$((adoptable_drift + 1))
    fi

    if [[ $mode == "adopt" ]]; then
      if [[ $status == "drift-missing" ]]; then
        continue
      fi

      if [[ $in_place -eq 0 ]]; then
        if [[ -z $resolved_output_dir ]]; then
          if [[ -n $output_dir ]]; then
            resolved_output_dir="$output_dir"
          else
            if [[ -w $ROOT ]]; then
              resolved_output_dir="$ROOT/.cache/shell-adopt/$(/bin/date +%Y%m%d-%H%M%S)"
            else
              resolved_output_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shell-adopt/$(/bin/date +%Y%m%d-%H%M%S)"
            fi
          fi
          mkdir -p "$resolved_output_dir"
        fi

        out_file="$resolved_output_dir/$(basename "$desired_path")"
        if [[ -e $out_file ]]; then
          out_file="$resolved_output_dir/$id.block"
        fi

        if export_actual_to_path "$id" "$out_file"; then
          log "staged adopted managed content: $id -> $out_file"
          staged=$((staged + 1))
        else
          log "failed to stage managed content for '$id'"
          errors=$((errors + 1))
        fi
      else
        if [[ $status == "conflict" && $force -eq 0 ]]; then
          log "refused in-place adopt for conflict target '$id' (use --force)"
          refused=$((refused + 1))
          continue
        fi

        if export_actual_to_path "$id" "$desired_path"; then
          adopted_hash="$(compute_actual_hash_for_target "$id" || true)"
          if [[ -z $adopted_hash ]]; then
            log "failed to compute adopted hash for '$id'"
            errors=$((errors + 1))
          elif ! write_last_applied_hash "$id" "$adopted_hash"; then
            log "failed to write lastApplied after adopt for '$id'"
            errors=$((errors + 1))
          else
            log "adopted managed content into desired file: $desired_path"
            adopted=$((adopted + 1))
          fi
        else
          log "failed to adopt managed content for '$id' into $desired_path"
          errors=$((errors + 1))
        fi
      fi
    elif [[ $mode == "apply" ]]; then
      if [[ $force -eq 0 ]]; then
        unresolved=$((unresolved + 1))
      else
        if write_target_from_desired "$id"; then
          applied_hash="$(compute_actual_hash_for_target "$id" || true)"
          if [[ -z $applied_hash ]]; then
            log "failed to compute applied hash for '$id'"
            errors=$((errors + 1))
          elif ! write_last_applied_hash "$id" "$applied_hash"; then
            log "failed to write lastApplied state for '$id'"
            errors=$((errors + 1))
          else
            applied=$((applied + 1))
            log "force-applied managed content: $id"
          fi
        else
          log "failed to force-apply managed content: $id"
          errors=$((errors + 1))
        fi
      fi
    fi
    ;;
  invalid-desired | actual-invalid | error | state-invalid)
    invalid=$((invalid + 1))
    log "invalid state for target '$id' ($status)"
    [[ -n $last_hash ]] && log "  lastApplied: $last_hash"
    ;;
  *)
    invalid=$((invalid + 1))
    log "unknown status '$status' for target '$id'"
    ;;
  esac
done < <(list_target_ids)

if [[ $selected -eq 0 ]]; then
  if [[ -n $target_filter ]]; then
    die "no target matched --target '$target_filter'"
  fi
  if [[ -n $shell_filter && $shell_filter != "all" ]]; then
    die "no target matched --shell '$shell_filter'"
  fi
  die "no shell targets selected"
fi

log "summary: checked=$checked in_sync=$in_sync pending=$pending state_stale=$state_stale drift=$drift conflicts=$conflicts drift_missing=$drift_missing missing=$missing untracked=$untracked applied=$applied staged=$staged adopted=$adopted refused=$refused unresolved=$unresolved invalid=$invalid errors=$errors"
log "managed dir: $managed_dir"
log "state dir: $state_dir"
[[ -n $resolved_output_dir ]] && log "staging dir: $resolved_output_dir"

if [[ $mode == "apply" ]] && { target_selected "zsh-zdotdir" || target_selected "zsh-local"; }; then
  if ! ensure_zshrc_compat_link; then
    errors=$((errors + 1))
  fi
fi

case "$mode" in
check)
  if [[ $invalid -gt 0 || $errors -gt 0 || $drift -gt 0 || $missing -gt 0 ]]; then
    exit 1
  fi
  exit 0
  ;;
adopt)
  if [[ $in_place -eq 0 ]]; then
    if [[ $invalid -gt 0 || $errors -gt 0 || $missing -gt 0 || $drift_missing -gt 0 ]]; then
      exit 1
    fi
    exit 0
  fi

  if [[ $invalid -gt 0 || $errors -gt 0 || $missing -gt 0 || $drift_missing -gt 0 || $refused -gt 0 || $adopted -lt $adoptable_drift ]]; then
    exit 1
  fi
  exit 0
  ;;
apply)
  if [[ $invalid -gt 0 || $errors -gt 0 || $unresolved -gt 0 ]]; then
    exit 1
  fi
  exit 0
  ;;
*)
  exit 1
  ;;
esac
