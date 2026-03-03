#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="terminal"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"
# shellcheck source=sync-core.sh
source_dotfiles_script "sync-core.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- terminal sync --check [--details] [--diff] [--profile <name>] [--dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- terminal sync --adopt [--details] [--diff] [--profile <name>] [--dir <path>] [--state-dir <path>] [--in-place] [--force] [--output-dir <path>]
  nix run .#dotfiles -- terminal sync --forget [--profile <name>] [--dir <path>] [--state-dir <path>]

Description:
  Compare Terminal.app profiles in ~/Library/Preferences/com.apple.Terminal.plist,
  repo .terminal files, and last-applied hashes.

Options:
  --check             Detect drift/missing/invalid (default mode)
  --adopt             Export current Terminal.app values for drifted profiles
  --forget            Remove last-applied hash state (all managed profiles or one via --profile)
  --details           Print concise per-profile drift details (font/cursor-related keys)
  --diff              Print unified diff (repo desired vs current actual)
  --profile <name>    Restrict to one profile name
  --dir <path>        Profiles directory (default: <repo>/apps/terminal)
  --state-dir <path>  Last-applied hash directory (default: $XDG_STATE_HOME/dotfiles/terminal-app/profiles)
  --in-place          With --adopt, overwrite repo files in place (default is staging output)
  --force             With --adopt --in-place, allow overwrite for 3-way conflicts
  --output-dir <path> With --adopt (staging mode), directory for exported .terminal files
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

subcommand="$1"
shift

if [[ $subcommand != "sync" ]]; then
  die "unknown terminal subcommand: $subcommand"
fi

mode="check"
profile_filter=""
details=0
show_diff=0
in_place=0
force=0
output_dir=""
default_profiles_dir=1

set_repo_root
profiles_dir="$ROOT/apps/terminal"
real_plist="$HOME/Library/Preferences/com.apple.Terminal.plist"
plist="$real_plist"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/terminal-app/profiles"
legacy_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/terminal/profiles"
work_plist=""
profile_index=""
profile_file_count=0
profile_invalid_seed=0

cleanup() {
  [[ -n ${work_plist:-} ]] && rm -f "$work_plist"
  [[ -n ${profile_index:-} ]] && rm -f "$profile_index"
}
trap cleanup EXIT

sync_cli_parse_script_option() {
  case "$1" in
  --profile)
    [[ $# -lt 2 ]] && die "missing value for --profile"
    profile_filter="$2"
    sync_core_cli_consumed=2
    return 0
    ;;
  --dir)
    [[ $# -lt 2 ]] && die "missing value for --dir"
    profiles_dir="$2"
    default_profiles_dir=0
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

sync_core_parse_cli_args 0 "$@"

sync_core_validate_adopt_flags "$mode" "$in_place" "$output_dir"
sync_core_validate_force_usage "$mode" "$in_place" "$force" 0 "--in-place/--force/--output-dir are only valid with --adopt"

if [[ $default_profiles_dir -eq 1 ]]; then
  worktree_root="$(resolve_repo_worktree_root_for "apps/terminal" || true)"
  if [[ -n $worktree_root ]]; then
    ROOT="$worktree_root"
    profiles_dir="$ROOT/apps/terminal"
  fi
fi

if [[ $mode == "adopt" && $in_place -eq 1 && ! -w $profiles_dir ]]; then
  die "profiles directory is not writable for --adopt --in-place: $profiles_dir (run from repo checkout or pass --dir)"
fi

if [[ $mode != "forget" ]]; then
  [[ -d $profiles_dir ]] || die "profiles directory not found: $profiles_dir"

  if [[ -n ${DOTFILES_TERMINAL_SYNC_PLIST:-} ]]; then
    if [[ ! -f ${DOTFILES_TERMINAL_SYNC_PLIST} ]]; then
      die "plist override does not exist: $DOTFILES_TERMINAL_SYNC_PLIST"
    fi
    plist="$DOTFILES_TERMINAL_SYNC_PLIST"
  else
    work_plist="$(mktemp "${TMPDIR:-/tmp}/terminal-sync.XXXXXX.plist")"
    if ! /usr/bin/defaults export com.apple.Terminal - >"$work_plist" 2>/dev/null; then
      if [[ -f $real_plist ]]; then
        cp "$real_plist" "$work_plist"
      else
        /usr/libexec/PlistBuddy -c "Clear dict" "$work_plist" >/dev/null 2>&1 || true
      fi
    fi
    plist="$work_plist"
  fi
fi

escape_plist_key() {
  local value="$1"

  value="$(printf '%s' "$value" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  printf '%s' "$value"
}

profile_state_key() {
  local name="$1"
  local short_hash prefix

  short_hash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1, 1, 12)}')"
  prefix="$(printf '%s' "$name" | /usr/bin/tr '[:space:]' '-' | /usr/bin/tr -cd '[:alnum:]._-')"
  [[ -z $prefix ]] && prefix="profile"

  printf '%s.%s\n' "$prefix" "$short_hash"
}

legacy_state_file() {
  local name="$1"
  local full_hash

  full_hash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  printf '%s/%s.sha256\n' "$legacy_state_dir" "$full_hash"
}

profile_name_from_file() {
  local file="$1"
  /usr/bin/plutil -extract name raw "$file" 2>/dev/null || true
}

has_profile() {
  local name="$1"
  local escaped_name
  escaped_name="$(escape_plist_key "$name")"
  /usr/libexec/PlistBuddy -c "Print :\"Window Settings\":\"$escaped_name\":name" "$plist" >/dev/null 2>&1
}

extract_profile_binary() {
  local name="$1"
  local out_file="$2"
  local tmp_xml escaped_name

  escaped_name="$(escape_plist_key "$name")"
  tmp_xml="$(mktemp)"

  if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$escaped_name\"" "$plist" >"$tmp_xml" 2>/dev/null; then
    rm -f "$tmp_xml"
    return 1
  fi

  if ! /usr/bin/plutil -convert binary1 -o "$out_file" "$tmp_xml" >/dev/null 2>&1; then
    rm -f "$tmp_xml"
    return 1
  fi

  rm -f "$tmp_xml"
  return 0
}

print_canonical_xml_from_file() {
  local file="$1"
  local out_file="$2"
  /usr/bin/plutil -convert xml1 -o "$out_file" "$file" >/dev/null 2>&1
}

print_canonical_xml_from_profile() {
  local name="$1"
  local out_file="$2"
  local tmp_xml escaped_name

  escaped_name="$(escape_plist_key "$name")"
  tmp_xml="$(mktemp)"

  if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$escaped_name\"" "$plist" >"$tmp_xml" 2>/dev/null; then
    rm -f "$tmp_xml"
    return 1
  fi

  if ! /usr/bin/plutil -convert xml1 -o "$out_file" "$tmp_xml" >/dev/null 2>&1; then
    rm -f "$tmp_xml"
    return 1
  fi

  rm -f "$tmp_xml"
  return 0
}

extract_raw_or_missing() {
  local file="$1"
  local key="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null || echo "<missing>"
}

extract_font_hint() {
  local file="$1"
  /usr/bin/plutil -extract Font raw -o - "$file" 2>/dev/null |
    /usr/bin/base64 -d 2>/dev/null |
    /usr/bin/strings |
    rg -m1 '0xProto|SFMono|Nerd|NF|Menlo|Monaco|JetBrainsMono|Hack|FiraCode' ||
    true
}

print_drift_details() {
  local name="$1"
  local src_file="$2"
  local last_hash="${3:-}"
  local cur_xml tmpdir escaped_name

  tmpdir="$(mktemp -d)"
  cur_xml="$tmpdir/current.xml"
  escaped_name="$(escape_plist_key "$name")"

  if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$escaped_name\"" "$plist" >"$cur_xml" 2>/dev/null; then
    rm -rf "$tmpdir"
    return 1
  fi

  log "drift details: $name"

  local repo_font cur_font
  repo_font="$(extract_font_hint "$src_file")"
  cur_font="$(extract_font_hint "$cur_xml")"
  if [[ -n $repo_font || -n $cur_font ]]; then
    log "  Font(repo): ${repo_font:-<unknown>}"
    log "  Font(current): ${cur_font:-<unknown>}"
  fi

  local keys key repo_val cur_val
  keys=(CursorType CursorBlink FontAntialias FontWidthSpacing FontHeightSpacing)
  for key in "${keys[@]}"; do
    repo_val="$(extract_raw_or_missing "$src_file" "$key")"
    cur_val="$(extract_raw_or_missing "$cur_xml" "$key")"
    if [[ $repo_val != "$cur_val" ]]; then
      log "  ${key}(repo): $repo_val"
      log "  ${key}(current): $cur_val"
    fi
  done

  local src_bin cur_bin src_hash cur_hash
  src_bin="$tmpdir/source.bin"
  cur_bin="$tmpdir/current.bin"
  /usr/bin/plutil -convert binary1 -o "$src_bin" "$src_file" >/dev/null 2>&1 || true
  /usr/bin/plutil -convert binary1 -o "$cur_bin" "$cur_xml" >/dev/null 2>&1 || true
  if [[ -f $src_bin && -f $cur_bin ]]; then
    src_hash="$(/usr/bin/shasum -a 256 "$src_bin" | /usr/bin/awk '{print $1}')"
    cur_hash="$(/usr/bin/shasum -a 256 "$cur_bin" | /usr/bin/awk '{print $1}')"
    log "  sha256(repo): $src_hash"
    log "  sha256(current): $cur_hash"
    if [[ -n $last_hash ]]; then
      log "  sha256(lastApplied): $last_hash"
    fi
  fi

  rm -rf "$tmpdir"
}

print_profile_diff() {
  local name="$1"
  local src_file="$2"
  local tmpdir repo_xml cur_xml

  tmpdir="$(mktemp -d)"
  repo_xml="$tmpdir/repo.xml"
  cur_xml="$tmpdir/current.xml"

  if ! print_canonical_xml_from_file "$src_file" "$repo_xml"; then
    rm -rf "$tmpdir"
    return 1
  fi

  if ! print_canonical_xml_from_profile "$name" "$cur_xml"; then
    rm -rf "$tmpdir"
    return 1
  fi

  log "diff: $name"
  /usr/bin/diff -u "$repo_xml" "$cur_xml" || true
  rm -rf "$tmpdir"
  return 0
}

adopt_profile_to_path() {
  local name="$1"
  local destination="$2"
  local tmpdir cur_xml out_tmp escaped_name

  tmpdir="$(mktemp -d)"
  cur_xml="$tmpdir/current.xml"
  out_tmp="$tmpdir/out.terminal"
  escaped_name="$(escape_plist_key "$name")"

  if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$escaped_name\"" "$plist" >"$cur_xml" 2>/dev/null; then
    rm -rf "$tmpdir"
    return 1
  fi
  if ! /usr/bin/plutil -convert xml1 -o "$out_tmp" "$cur_xml" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi

  mkdir -p "$(dirname "$destination")"
  mv "$out_tmp" "$destination"
  rm -rf "$tmpdir"
  return 0
}

build_profile_index_for_sync() {
  local file name

  profile_index="$(mktemp)"
  profile_file_count=0
  profile_invalid_seed=0

  while IFS= read -r file; do
    [[ -z $file ]] && continue
    profile_file_count=$((profile_file_count + 1))

    name="$(profile_name_from_file "$file")"
    if [[ -z $name ]]; then
      log "invalid profile file (missing 'name'): $file"
      profile_invalid_seed=$((profile_invalid_seed + 1))
      continue
    fi

    printf '%s|%s|%s\n' "$name" "$file" "$plist" >>"$profile_index"
  done < <(find "$profiles_dir" -maxdepth 1 -type f -name '*.terminal' | sort)
}

build_profile_index_for_forget() {
  local file name

  profile_index="$(mktemp)"
  profile_file_count=0
  profile_invalid_seed=0

  if [[ -n $profile_filter ]]; then
    printf '%s||\n' "$profile_filter" >"$profile_index"
    profile_file_count=1
    return 0
  fi

  [[ -d $profiles_dir ]] || die "profiles directory not found: $profiles_dir"

  while IFS= read -r file; do
    [[ -z $file ]] && continue
    profile_file_count=$((profile_file_count + 1))

    name="$(profile_name_from_file "$file")"
    if [[ -z $name ]]; then
      log "invalid profile file (missing 'name'): $file"
      profile_invalid_seed=$((profile_invalid_seed + 1))
      continue
    fi

    printf '%s|%s|\n' "$name" "$file" >>"$profile_index"
  done < <(find "$profiles_dir" -maxdepth 1 -type f -name '*.terminal' | sort)
}

if [[ $mode == "forget" ]]; then
  build_profile_index_for_forget
else
  build_profile_index_for_sync
fi

sync_adapter_list_items() {
  cat "$profile_index"
}

sync_adapter_is_selected() {
  local id="$1"

  if [[ -n $profile_filter && $id != "$profile_filter" ]]; then
    return 1
  fi

  return 0
}

sync_adapter_state_key() {
  local id="$1"
  profile_state_key "$id"
}

sync_adapter_read_last_applied_hash() {
  local id="$1"
  local state_file legacy_file

  state_file="$(sync_core_state_file_for_key "$(profile_state_key "$id")")"
  if [[ -f $state_file ]]; then
    head -n 1 "$state_file" | tr -d '[:space:]'
    return 0
  fi

  legacy_file="$(legacy_state_file "$id")"
  if [[ -f $legacy_file ]]; then
    head -n 1 "$legacy_file" | tr -d '[:space:]'
  fi
}

sync_adapter_forget_last_applied_hash() {
  local id="$1"
  local state_file legacy_file removed=0

  state_file="$(sync_core_state_file_for_key "$(profile_state_key "$id")")"
  if [[ -f $state_file ]]; then
    rm -f "$state_file"
    removed=1
  fi

  legacy_file="$(legacy_state_file "$id")"
  if [[ -f $legacy_file ]]; then
    rm -f "$legacy_file"
    removed=1
  fi

  return $((1 - removed))
}

sync_adapter_extract_desired() {
  local _id="$1"
  local output_file="$2"
  local desired_meta="$3"

  [[ -f $desired_meta ]] || return 1
  /usr/bin/plutil -convert binary1 -o "$output_file" "$desired_meta" >/dev/null 2>&1
}

sync_adapter_extract_actual() {
  local id="$1"
  local output_file="$2"

  if ! has_profile "$id"; then
    return 2
  fi

  extract_profile_binary "$id" "$output_file"
}

sync_adapter_write_desired_to_actual() {
  return 1
}

sync_adapter_export_actual() {
  local id="$1"
  local destination="$2"
  adopt_profile_to_path "$id" "$destination"
}

sync_adapter_stage_fallback_basename() {
  local id="$1"
  printf '%s.terminal\n' "$(profile_state_key "$id")"
}

sync_adapter_print_details() {
  local id="$1"
  local status="$2"
  local _desired_hash="$3"
  local _actual_hash="$4"
  local last_hash="$5"
  local desired_meta="$6"

  if [[ $status != "drift-missing" ]]; then
    print_drift_details "$id" "$desired_meta" "$last_hash" || true
  fi
}

sync_adapter_print_diff() {
  local id="$1"
  local _status="$2"
  local desired_meta="$3"
  print_profile_diff "$id" "$desired_meta"
}

sync_adapter_log_status() {
  local id="$1"
  local status="$2"
  local desired_meta="$3"
  local _actual_meta="$4"
  local last_hash="$5"

  case "$status" in
  safe-update)
    log "safe update pending: $id ($desired_meta)"
    log "  repo changed; current still matches lastApplied, apply can overwrite safely"
    ;;
  in-sync-untracked)
    log "in sync but no lastApplied state: $id"
    ;;
  state-stale)
    log "state stale (desired==actual, lastApplied is old): $id"
    ;;
  missing)
    log "missing in Terminal.app: $id"
    ;;
  drift-untracked | drift-missing | drift-external | conflict)
    log "drift detected: $id ($desired_meta)"
    [[ -n $last_hash ]] && log "  lastApplied: $last_hash"
    case "$status" in
    drift-untracked)
      log "  reason: profile exists without lastApplied and differs from repo"
      ;;
    drift-missing)
      log "  reason: profile missing but lastApplied exists"
      ;;
    drift-external)
      log "  reason: current changed outside dotfiles (desired==lastApplied, actual!=lastApplied)"
      ;;
    conflict)
      log "  reason: both repo and current changed from lastApplied"
      ;;
    esac
    ;;
  esac
}

sync_adapter_on_no_selection() {
  if [[ -n $profile_filter ]]; then
    die "no profile file matched --profile '$profile_filter' in $profiles_dir"
  fi
  die "no .terminal files found in $profiles_dir"
}

sync_adapter_print_summary() {
  if [[ $mode == "forget" ]]; then
    log "summary: forgotten=$sync_core_forgotten missing_state=$sync_core_missing_state invalid=$sync_core_invalid"
    return 0
  fi

  log "summary: checked=$sync_core_checked in_sync=$sync_core_in_sync pending=$sync_core_pending state_stale=$sync_core_state_stale drift=$sync_core_drift conflicts=$sync_core_conflicts drift_missing=$sync_core_drift_missing missing=$sync_core_missing untracked=$sync_core_untracked staged=$sync_core_staged adopted=$sync_core_adopted refused=$sync_core_refused invalid=$sync_core_invalid errors=$sync_core_errors"
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
sync_core_staging_subdir="terminal-adopt"
sync_core_invalid_desired_status="invalid"
sync_core_invalid_actual_status="error"
sync_core_error_status="error"
sync_core_invalid_seed="$profile_invalid_seed"
sync_core_forget_invalid_seed="$profile_invalid_seed"

if sync_core_run; then
  exit 0
fi

exit 1
