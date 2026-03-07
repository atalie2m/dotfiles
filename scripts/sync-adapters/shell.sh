#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="sync-shell"
ADAPTER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$ADAPTER_DIR/../lib/load-lib.sh"
# shellcheck source=sync-adapters/shell/common.sh
source "$ADAPTER_DIR/shell/common.sh"
# shellcheck source=sync-adapters/shell/write.sh
source "$ADAPTER_DIR/shell/write.sh"
# shellcheck source=sync-adapters/shell/classify.sh
source "$ADAPTER_DIR/shell/classify.sh"
# shellcheck source=sync-adapters/shell/report.sh
source "$ADAPTER_DIR/shell/report.sh"
# shellcheck source=sync-adapters/shell/apply.sh
source "$ADAPTER_DIR/shell/apply.sh"

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
# shellcheck disable=SC2317
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

# shellcheck disable=SC2317
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
