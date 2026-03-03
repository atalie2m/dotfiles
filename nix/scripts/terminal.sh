#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="terminal"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

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

trap 'if [[ -n ${work_plist:-} ]]; then rm -f "$work_plist"; fi' EXIT

resolve_repo_worktree_root() {
  local candidate=""

  if command -v git >/dev/null 2>&1; then
    candidate="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n $candidate && -f $candidate/flake.nix && -d $candidate/apps/terminal && -d $candidate/nix/scripts ]]; then
      cd "$candidate" && pwd
      return 0
    fi
  fi

  if [[ -f "$(pwd)/flake.nix" && -d "$(pwd)/apps/terminal" && -d "$(pwd)/nix/scripts" ]]; then
    pwd
    return 0
  fi

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    mode="check"
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
  --profile)
    [[ $# -lt 2 ]] && die "missing value for --profile"
    profile_filter="$2"
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
  --dir)
    [[ $# -lt 2 ]] && die "missing value for --dir"
    profiles_dir="$2"
    default_profiles_dir=0
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

if [[ $mode != "adopt" && ($in_place -eq 1 || $force -eq 1 || -n $output_dir) ]]; then
  die "--in-place/--force/--output-dir are only valid with --adopt"
fi

if [[ $mode == "adopt" && $in_place -eq 1 && -n $output_dir ]]; then
  die "--output-dir cannot be used with --adopt --in-place"
fi

if [[ $default_profiles_dir -eq 1 ]]; then
  worktree_root="$(resolve_repo_worktree_root || true)"
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

profile_state_key() {
  local name="$1"
  local short_hash prefix

  short_hash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1, 1, 12)}')"
  prefix="$(printf '%s' "$name" | /usr/bin/tr '[:space:]' '-' | /usr/bin/tr -cd '[:alnum:]._-')"
  [[ -z $prefix ]] && prefix="profile"

  printf '%s.%s\n' "$prefix" "$short_hash"
}

profile_state_file() {
  local name="$1"
  local key

  key="$(profile_state_key "$name")"
  printf '%s/%s.sha256\n' "$state_dir" "$key"
}

legacy_state_file() {
  local name="$1"
  local full_hash

  full_hash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  printf '%s/%s.sha256\n' "$legacy_state_dir" "$full_hash"
}

read_last_applied_hash() {
  local name="$1"
  local state_file legacy_file

  state_file="$(profile_state_file "$name")"
  if [[ -f $state_file ]]; then
    head -n 1 "$state_file" | tr -d '[:space:]'
    return 0
  fi

  legacy_file="$(legacy_state_file "$name")"
  if [[ -f $legacy_file ]]; then
    head -n 1 "$legacy_file" | tr -d '[:space:]'
  fi
}

write_last_applied_hash() {
  local name="$1"
  local hash="$2"
  local state_file

  state_file="$(profile_state_file "$name")"
  mkdir -p "$state_dir"
  printf '%s\n' "$hash" >"$state_file"
}

forget_last_applied_hash() {
  local name="$1"
  local state_file legacy_file removed=0

  state_file="$(profile_state_file "$name")"
  if [[ -f $state_file ]]; then
    rm -f "$state_file"
    removed=1
  fi

  legacy_file="$(legacy_state_file "$name")"
  if [[ -f $legacy_file ]]; then
    rm -f "$legacy_file"
    removed=1
  fi

  return $((1 - removed))
}

has_profile() {
  local name="$1"
  local escaped_name
  escaped_name="$(escape_plist_key "$name")"
  /usr/libexec/PlistBuddy -c "Print :\"Window Settings\":\"$escaped_name\":name" "$plist" >/dev/null 2>&1
}

profile_name_from_file() {
  local file="$1"
  /usr/bin/plutil -extract name raw "$file" 2>/dev/null || true
}

canonical_hash_from_file() {
  local file="$1"
  local tmpdir src_bin

  tmpdir="$(mktemp -d)"
  src_bin="$tmpdir/source.bin"

  if ! /usr/bin/plutil -convert binary1 -o "$src_bin" "$file" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi

  /usr/bin/shasum -a 256 "$src_bin" | /usr/bin/awk '{print $1}'
  rm -rf "$tmpdir"
  return 0
}

canonical_hash_from_profile() {
  local name="$1"
  local tmpdir cur_xml cur_bin escaped_name

  tmpdir="$(mktemp -d)"
  cur_xml="$tmpdir/current.xml"
  cur_bin="$tmpdir/current.bin"
  escaped_name="$(escape_plist_key "$name")"

  if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$escaped_name\"" "$plist" >"$cur_xml" 2>/dev/null; then
    rm -rf "$tmpdir"
    return 1
  fi
  if ! /usr/bin/plutil -convert binary1 -o "$cur_bin" "$cur_xml" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi

  /usr/bin/shasum -a 256 "$cur_bin" | /usr/bin/awk '{print $1}'
  rm -rf "$tmpdir"
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
  local tmpdir cur_xml escaped_name

  tmpdir="$(mktemp -d)"
  cur_xml="$tmpdir/current.xml"
  escaped_name="$(escape_plist_key "$name")"

  if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$escaped_name\"" "$plist" >"$cur_xml" 2>/dev/null; then
    rm -rf "$tmpdir"
    return 1
  fi

  if ! /usr/bin/plutil -convert xml1 -o "$out_file" "$cur_xml" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

is_sha256_hash() {
  local value="$1"
  [[ $value =~ ^[0-9a-fA-F]{64}$ ]]
}

escape_plist_key() {
  local value="$1"

  value="$(printf '%s' "$value" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  printf '%s' "$value"
}

determine_profile_status() {
  local name="$1"
  local file="$2"
  local desired_hash actual_hash="" last_hash=""

  desired_hash="$(canonical_hash_from_file "$file" || true)"
  if [[ -z $desired_hash ]]; then
    printf 'invalid|%s||\n' "$name"
    return 0
  fi

  if has_profile "$name"; then
    actual_hash="$(canonical_hash_from_profile "$name" || true)"
    if [[ -z $actual_hash ]]; then
      printf 'error|%s|%s||\n' "$name" "$desired_hash"
      return 0
    fi
  fi

  last_hash="$(read_last_applied_hash "$name")"

  if [[ -n $last_hash ]]; then
    if ! is_sha256_hash "$last_hash"; then
      printf 'state-invalid|%s|%s|%s|%s\n' "$name" "$desired_hash" "$actual_hash" "$last_hash"
      return 0
    fi

    if [[ -z $actual_hash ]]; then
      printf 'drift-missing|%s|%s||%s\n' "$name" "$desired_hash" "$last_hash"
      return 0
    fi

    if [[ $actual_hash == "$last_hash" ]]; then
      if [[ $actual_hash == "$desired_hash" ]]; then
        printf 'in-sync|%s|%s|%s|%s\n' "$name" "$desired_hash" "$actual_hash" "$last_hash"
      else
        printf 'safe-update|%s|%s|%s|%s\n' "$name" "$desired_hash" "$actual_hash" "$last_hash"
      fi
      return 0
    fi

    if [[ $actual_hash == "$desired_hash" ]]; then
      printf 'state-stale|%s|%s|%s|%s\n' "$name" "$desired_hash" "$actual_hash" "$last_hash"
      return 0
    fi

    if [[ $desired_hash == "$last_hash" ]]; then
      printf 'drift-external|%s|%s|%s|%s\n' "$name" "$desired_hash" "$actual_hash" "$last_hash"
      return 0
    fi

    printf 'conflict|%s|%s|%s|%s\n' "$name" "$desired_hash" "$actual_hash" "$last_hash"
    return 0
  fi

  if [[ -z $actual_hash ]]; then
    printf 'missing|%s|%s||\n' "$name" "$desired_hash"
    return 0
  fi

  if [[ $actual_hash == "$desired_hash" ]]; then
    printf 'in-sync-untracked|%s|%s|%s|\n' "$name" "$desired_hash" "$actual_hash"
  else
    printf 'drift-untracked|%s|%s|%s|\n' "$name" "$desired_hash" "$actual_hash"
  fi
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
  local tmpdir cur_xml escaped_name

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

forget_mode() {
  local forgotten=0 missing_state=0 invalid=0

  if [[ -n $profile_filter ]]; then
    if forget_last_applied_hash "$profile_filter"; then
      forgotten=$((forgotten + 1))
      log "forgot lastApplied state: $profile_filter"
    else
      missing_state=$((missing_state + 1))
      log "no lastApplied state found: $profile_filter"
    fi
  else
    [[ -d $profiles_dir ]] || die "profiles directory not found: $profiles_dir"

    while IFS= read -r file; do
      [[ -z $file ]] && continue

      name="$(profile_name_from_file "$file")"
      if [[ -z $name ]]; then
        log "invalid profile file (missing 'name'): $file"
        invalid=$((invalid + 1))
        continue
      fi

      if forget_last_applied_hash "$name"; then
        forgotten=$((forgotten + 1))
      else
        missing_state=$((missing_state + 1))
      fi
    done < <(find "$profiles_dir" -maxdepth 1 -type f -name '*.terminal' | sort)
  fi

  log "summary: forgotten=$forgotten missing_state=$missing_state invalid=$invalid"
  if [[ $invalid -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

if [[ $mode == "forget" ]]; then
  forget_mode
fi

checked=0
in_sync=0
pending=0
untracked=0
state_stale=0
drift=0
drift_missing=0
conflicts=0
missing=0
invalid=0
staged=0
adopted=0
refused=0
errors=0
adoptable_drift=0

resolved_output_dir=""

while IFS= read -r file; do
  [[ -z $file ]] && continue

  name="$(profile_name_from_file "$file")"
  if [[ -z $name ]]; then
    log "invalid profile file (missing 'name'): $file"
    invalid=$((invalid + 1))
    continue
  fi

  if [[ -n $profile_filter && $name != "$profile_filter" ]]; then
    continue
  fi

  checked=$((checked + 1))

  status_line="$(determine_profile_status "$name" "$file")"
  IFS='|' read -r status _ desired_hash actual_hash last_hash <<<"$status_line"

  case "$status" in
  in-sync)
    in_sync=$((in_sync + 1))
    ;;
  safe-update)
    pending=$((pending + 1))
    log "safe update pending: $name ($file)"
    log "  repo changed; current still matches lastApplied, apply can overwrite safely"
    ;;
  in-sync-untracked)
    in_sync=$((in_sync + 1))
    untracked=$((untracked + 1))
    log "in sync but no lastApplied state: $name"
    ;;
  state-stale)
    in_sync=$((in_sync + 1))
    state_stale=$((state_stale + 1))
    log "state stale (desired==actual, lastApplied is old): $name"
    ;;
  missing)
    missing=$((missing + 1))
    log "missing in Terminal.app: $name"
    ;;
  invalid | error | state-invalid)
    invalid=$((invalid + 1))
    log "invalid state for profile '$name' ($status)"
    [[ -n $last_hash ]] && log "  lastApplied: $last_hash"
    ;;
  drift-untracked | drift-missing | drift-external | conflict)
    drift=$((drift + 1))
    [[ $status == "conflict" ]] && conflicts=$((conflicts + 1))
    [[ $status == "drift-missing" ]] && drift_missing=$((drift_missing + 1))

    log "drift detected: $name ($file)"
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

    if [[ $details -eq 1 && $status != "drift-missing" ]]; then
      print_drift_details "$name" "$file" "$last_hash" || true
    fi

    if [[ $show_diff -eq 1 && $status != "drift-missing" ]]; then
      print_profile_diff "$name" "$file" || true
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
              resolved_output_dir="$ROOT/.cache/terminal-adopt/$(/bin/date +%Y%m%d-%H%M%S)"
            else
              resolved_output_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/terminal-adopt/$(/bin/date +%Y%m%d-%H%M%S)"
            fi
          fi
          mkdir -p "$resolved_output_dir"
        fi

        out_file="$resolved_output_dir/$(basename "$file")"
        if [[ -e $out_file ]]; then
          out_file="$resolved_output_dir/$(profile_state_key "$name").terminal"
        fi

        if adopt_profile_to_path "$name" "$out_file"; then
          log "staged adopted profile: $name -> $out_file"
          staged=$((staged + 1))
        else
          log "failed to stage profile '$name'"
          errors=$((errors + 1))
        fi
      else
        if [[ $status == "conflict" && $force -eq 0 ]]; then
          log "refused in-place adopt for conflict profile '$name' (use --force)"
          refused=$((refused + 1))
          continue
        fi

        if adopt_profile_to_path "$name" "$file"; then
          adopted_hash="$(canonical_hash_from_profile "$name" || true)"
          if [[ -z $adopted_hash ]]; then
            log "failed to compute adopted hash for '$name'"
            errors=$((errors + 1))
          else
            write_last_applied_hash "$name" "$adopted_hash"
            log "adopted Terminal.app profile into repo file: $file"
            adopted=$((adopted + 1))
          fi
        else
          log "failed to adopt profile '$name' into $file"
          errors=$((errors + 1))
        fi
      fi
    fi
    ;;
  *)
    invalid=$((invalid + 1))
    log "unknown status '$status' for profile '$name'"
    ;;
  esac
done < <(find "$profiles_dir" -maxdepth 1 -type f -name '*.terminal' | sort)

if [[ $checked -eq 0 ]]; then
  if [[ -n $profile_filter ]]; then
    die "no profile file matched --profile '$profile_filter' in $profiles_dir"
  fi
  die "no .terminal files found in $profiles_dir"
fi

log "summary: checked=$checked in_sync=$in_sync pending=$pending state_stale=$state_stale drift=$drift conflicts=$conflicts drift_missing=$drift_missing missing=$missing untracked=$untracked staged=$staged adopted=$adopted refused=$refused invalid=$invalid errors=$errors"
log "state dir: $state_dir"
[[ -n $resolved_output_dir ]] && log "staging dir: $resolved_output_dir"

if [[ $mode == "check" ]]; then
  if [[ $invalid -gt 0 || $errors -gt 0 || $drift -gt 0 || $missing -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

if [[ $mode == "adopt" ]]; then
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
fi

exit 1
