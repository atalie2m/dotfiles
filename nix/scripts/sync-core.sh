#!/usr/bin/env bash
set -euo pipefail

_sync_core_has_function() {
  declare -f "$1" >/dev/null 2>&1
}

sync_core_is_sha256_hash() {
  local value="$1"
  [[ $value =~ ^[0-9a-fA-F]{64}$ ]]
}

sync_core_hash_file() {
  local file="$1"
  /usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}'
}

sync_core_validate_adopt_flags() {
  local mode="$1"
  local in_place="$2"
  local output_dir="$3"

  if [[ $mode != "adopt" && ($in_place -eq 1 || -n $output_dir) ]]; then
    die "--in-place/--output-dir are only valid with --adopt"
  fi

  if [[ $mode == "adopt" && $in_place -eq 1 && -n $output_dir ]]; then
    die "--output-dir cannot be used with --adopt --in-place"
  fi
}

sync_core_validate_force_usage() {
  local mode="$1"
  local in_place="$2"
  local force="$3"
  local allow_apply_force="$4"
  local message="$5"

  if [[ $force -ne 1 ]]; then
    return 0
  fi

  case "$mode" in
  apply)
    if [[ $allow_apply_force -ne 1 ]]; then
      die "$message"
    fi
    ;;
  adopt)
    if [[ $in_place -ne 1 ]]; then
      die "$message"
    fi
    ;;
  *)
    die "$message"
    ;;
  esac
}

sync_core_parse_cli_args() {
  local allow_apply="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --apply)
      if [[ $allow_apply -ne 1 ]]; then
        die "unknown option: --apply"
      fi
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
    --details)
      details=1
      shift
      ;;
    --diff)
      show_diff=1
      shift
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
    *)
      if _sync_core_has_function sync_cli_parse_script_option; then
        sync_core_cli_consumed=0
        if sync_cli_parse_script_option "$@"; then
          if [[ ${sync_core_cli_consumed:-0} -le 0 ]]; then
            die "sync_cli_parse_script_option must set sync_core_cli_consumed (>0)"
          fi
          shift "$sync_core_cli_consumed"
          continue
        fi
      fi

      if [[ $1 == --* ]]; then
        die "unknown option: $1"
      fi
      die "unexpected argument: $1"
      ;;
    esac
  done
}

sync_core_state_file_for_key() {
  local key="$1"
  printf '%s/%s.sha256\n' "$sync_core_state_dir" "$key"
}

sync_core_read_last_applied_hash() {
  local id="$1"
  local state_file key

  if _sync_core_has_function sync_adapter_read_last_applied_hash; then
    sync_adapter_read_last_applied_hash "$id"
    return 0
  fi

  key="$(sync_adapter_state_key "$id")"
  state_file="$(sync_core_state_file_for_key "$key")"
  if [[ -f $state_file ]]; then
    head -n 1 "$state_file" | tr -d '[:space:]'
  fi
}

sync_core_write_last_applied_hash() {
  local id="$1"
  local hash="$2"
  local state_file key

  if _sync_core_has_function sync_adapter_write_last_applied_hash; then
    sync_adapter_write_last_applied_hash "$id" "$hash"
    return $?
  fi

  key="$(sync_adapter_state_key "$id")"
  state_file="$(sync_core_state_file_for_key "$key")"
  mkdir -p "$sync_core_state_dir"
  printf '%s\n' "$hash" >"$state_file"
}

sync_core_forget_last_applied_hash() {
  local id="$1"
  local state_file key

  if _sync_core_has_function sync_adapter_forget_last_applied_hash; then
    sync_adapter_forget_last_applied_hash "$id"
    return $?
  fi

  key="$(sync_adapter_state_key "$id")"
  state_file="$(sync_core_state_file_for_key "$key")"
  if [[ -f $state_file ]]; then
    rm -f "$state_file"
    return 0
  fi
  return 1
}

sync_core_evaluate_three_way_status() {
  local desired_hash="$1"
  local actual_hash="$2"
  local last_hash="$3"

  if [[ -n $last_hash ]]; then
    if [[ -z $actual_hash ]]; then
      printf '%s\n' "drift-missing"
      return 0
    fi

    if [[ $actual_hash == "$last_hash" ]]; then
      if [[ $actual_hash == "$desired_hash" ]]; then
        printf '%s\n' "in-sync"
      else
        printf '%s\n' "safe-update"
      fi
      return 0
    fi

    if [[ $actual_hash == "$desired_hash" ]]; then
      printf '%s\n' "state-stale"
      return 0
    fi

    if [[ $desired_hash == "$last_hash" ]]; then
      printf '%s\n' "drift-external"
      return 0
    fi

    printf '%s\n' "conflict"
    return 0
  fi

  if [[ -z $actual_hash ]]; then
    printf '%s\n' "missing"
    return 0
  fi

  if [[ $actual_hash == "$desired_hash" ]]; then
    printf '%s\n' "in-sync-untracked"
  else
    printf '%s\n' "drift-untracked"
  fi
}

sync_core_determine_item_status() {
  local id="$1"
  local desired_meta="$2"
  local actual_meta="$3"
  local desired_tmp actual_tmp rc
  local desired_hash="" actual_hash="" last_hash="" status=""

  desired_tmp="$(mktemp)"
  actual_tmp="$(mktemp)"

  last_hash="$(sync_core_read_last_applied_hash "$id")"

  if ! sync_adapter_extract_desired "$id" "$desired_tmp" "$desired_meta"; then
    rm -f "$desired_tmp" "$actual_tmp"
    printf '%s|%s|||%s|%s|%s\n' "${sync_core_invalid_desired_status:-invalid-desired}" "$id" "$last_hash" "$desired_meta" "$actual_meta"
    return 0
  fi

  desired_hash="$(sync_core_hash_file "$desired_tmp" || true)"
  if [[ -z $desired_hash ]]; then
    rm -f "$desired_tmp" "$actual_tmp"
    printf '%s|%s|||%s|%s|%s\n' "${sync_core_invalid_desired_status:-invalid-desired}" "$id" "$last_hash" "$desired_meta" "$actual_meta"
    return 0
  fi

  if sync_adapter_extract_actual "$id" "$actual_tmp" "$actual_meta"; then
    actual_hash="$(sync_core_hash_file "$actual_tmp" || true)"
    if [[ -z $actual_hash ]]; then
      rm -f "$desired_tmp" "$actual_tmp"
      printf '%s|%s|%s||%s|%s|%s\n' "${sync_core_error_status:-error}" "$id" "$desired_hash" "$last_hash" "$desired_meta" "$actual_meta"
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
      printf '%s|%s|%s||%s|%s|%s\n' "${sync_core_invalid_actual_status:-actual-invalid}" "$id" "$desired_hash" "$last_hash" "$desired_meta" "$actual_meta"
      return 0
      ;;
    *)
      rm -f "$desired_tmp" "$actual_tmp"
      printf '%s|%s|%s||%s|%s|%s\n' "${sync_core_error_status:-error}" "$id" "$desired_hash" "$last_hash" "$desired_meta" "$actual_meta"
      return 0
      ;;
    esac
  fi

  rm -f "$desired_tmp" "$actual_tmp"

  if [[ -n $last_hash ]] && ! sync_core_is_sha256_hash "$last_hash"; then
    printf '%s|%s|%s|%s|%s|%s|%s\n' "state-invalid" "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_meta" "$actual_meta"
    return 0
  fi

  status="$(sync_core_evaluate_three_way_status "$desired_hash" "$actual_hash" "$last_hash")"
  printf '%s|%s|%s|%s|%s|%s|%s\n' "$status" "$id" "$desired_hash" "$actual_hash" "$last_hash" "$desired_meta" "$actual_meta"
}

sync_core_compute_actual_hash() {
  local id="$1"
  local actual_meta="$2"
  local tmp_actual hash

  tmp_actual="$(mktemp)"
  if ! sync_adapter_extract_actual "$id" "$tmp_actual" "$actual_meta"; then
    rm -f "$tmp_actual"
    return 1
  fi

  hash="$(sync_core_hash_file "$tmp_actual" || true)"
  rm -f "$tmp_actual"
  [[ -n $hash ]] || return 1
  printf '%s\n' "$hash"
}

sync_core_log_status() {
  local id="$1"
  local status="$2"
  local desired_meta="$3"
  local actual_meta="$4"
  local last_hash="$5"

  if _sync_core_has_function sync_adapter_log_status; then
    sync_adapter_log_status "$id" "$status" "$desired_meta" "$actual_meta" "$last_hash"
    return 0
  fi

  case "$status" in
  safe-update)
    log "safe update pending: $id"
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
    ;;
  *)
    log "status: $status ($id)"
    ;;
  esac
}

sync_core_log_action() {
  local action="$1"
  shift

  if _sync_core_has_function sync_adapter_log_action; then
    sync_adapter_log_action "$action" "$@"
    return 0
  fi

  case "$action" in
  forgot)
    log "forgot lastApplied state: $1"
    ;;
  no-state)
    log "no lastApplied state found: $1"
    ;;
  apply-ok)
    log "applied managed content: $1"
    ;;
  apply-force-ok)
    log "force-applied managed content: $1"
    ;;
  apply-failed)
    log "failed to apply managed content: $1"
    ;;
  apply-force-failed)
    log "failed to force-apply managed content: $1"
    ;;
  state-write-missing-ok)
    log "wrote missing lastApplied state: $1"
    ;;
  state-write-missing-failed)
    log "failed to write missing lastApplied state: $1"
    ;;
  state-refresh-ok)
    log "refreshed lastApplied state: $1"
    ;;
  state-refresh-failed)
    log "failed to refresh lastApplied state: $1"
    ;;
  staged-ok)
    log "staged adopted content: $1 -> $2"
    ;;
  staged-failed)
    log "failed to stage content for '$1'"
    ;;
  adopt-ok)
    log "adopted local content into desired file: $2"
    ;;
  adopt-failed)
    log "failed to adopt content for '$1' into $2"
    ;;
  adopt-refused)
    log "refused in-place adopt for conflict '$1' (use --force)"
    ;;
  hash-failed)
    log "failed to compute actual hash for '$1'"
    ;;
  state-write-failed)
    log "failed to write lastApplied state for '$1'"
    ;;
  unknown-status)
    log "unknown status '$2' for '$1'"
    ;;
  invalid)
    log "invalid state for '$1' ($2)"
    ;;
  *)
    ;;
  esac
}

sync_core_is_invalid_status() {
  local status="$1"

  case "$status" in
  invalid | invalid-desired | actual-invalid | error | state-invalid)
    return 0
    ;;
  esac

  if [[ -n ${sync_core_invalid_desired_status:-} && $status == "$sync_core_invalid_desired_status" ]]; then
    return 0
  fi

  if [[ -n ${sync_core_invalid_actual_status:-} && $status == "$sync_core_invalid_actual_status" ]]; then
    return 0
  fi

  if [[ -n ${sync_core_error_status:-} && $status == "$sync_core_error_status" ]]; then
    return 0
  fi

  return 1
}

sync_core_require_adapter() {
  local required=(
    sync_adapter_list_items
    sync_adapter_is_selected
    sync_adapter_state_key
    sync_adapter_extract_desired
    sync_adapter_extract_actual
    sync_adapter_write_desired_to_actual
    sync_adapter_export_actual
    sync_adapter_on_no_selection
    sync_adapter_print_summary
  )
  local fn

  for fn in "${required[@]}"; do
    if ! _sync_core_has_function "$fn"; then
      die "sync adapter missing required function: $fn"
    fi
  done
}

sync_core_resolve_output_dir() {
  if [[ -n ${sync_core_resolved_output_dir:-} ]]; then
    return 0
  fi

  if [[ -n $sync_core_output_dir ]]; then
    sync_core_resolved_output_dir="$sync_core_output_dir"
  else
    local stamp
    stamp="$(/bin/date +%Y%m%d-%H%M%S)"
    if [[ -w $sync_core_root ]]; then
      sync_core_resolved_output_dir="$sync_core_root/.cache/$sync_core_staging_subdir/$stamp"
    else
      sync_core_resolved_output_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/$sync_core_staging_subdir/$stamp"
    fi
  fi

  mkdir -p "$sync_core_resolved_output_dir"
}

sync_core_stage_basename_for_item() {
  local id="$1"
  local desired_meta="$2"
  local actual_meta="$3"

  if _sync_core_has_function sync_adapter_stage_basename; then
    sync_adapter_stage_basename "$id" "$desired_meta" "$actual_meta"
    return 0
  fi

  basename "$desired_meta"
}

sync_core_stage_fallback_basename_for_item() {
  local id="$1"
  local desired_meta="$2"
  local actual_meta="$3"

  if _sync_core_has_function sync_adapter_stage_fallback_basename; then
    sync_adapter_stage_fallback_basename "$id" "$desired_meta" "$actual_meta"
    return 0
  fi

  printf '%s.adopt\n' "$id"
}

sync_core_inplace_destination_for_item() {
  local id="$1"
  local desired_meta="$2"
  local actual_meta="$3"

  if _sync_core_has_function sync_adapter_inplace_destination; then
    sync_adapter_inplace_destination "$id" "$desired_meta" "$actual_meta"
    return 0
  fi

  printf '%s\n' "$desired_meta"
}

sync_core_apply_item() {
  local id="$1"
  local desired_meta="$2"
  local actual_meta="$3"
  local forced="$4"
  local applied_hash=""

  if sync_adapter_write_desired_to_actual "$id" "$desired_meta" "$actual_meta"; then
    applied_hash="$(sync_core_compute_actual_hash "$id" "$actual_meta" || true)"
    if [[ -z $applied_hash ]]; then
      sync_core_log_action "hash-failed" "$id"
      sync_core_errors=$((sync_core_errors + 1))
      return 1
    fi

    if ! sync_core_write_last_applied_hash "$id" "$applied_hash"; then
      sync_core_log_action "state-write-failed" "$id"
      sync_core_errors=$((sync_core_errors + 1))
      return 1
    fi

    sync_core_applied=$((sync_core_applied + 1))
    if [[ $forced -eq 1 ]]; then
      sync_core_log_action "apply-force-ok" "$id"
    else
      sync_core_log_action "apply-ok" "$id"
    fi
    return 0
  fi

  if [[ $forced -eq 1 ]]; then
    sync_core_log_action "apply-force-failed" "$id"
  else
    sync_core_log_action "apply-failed" "$id"
  fi
  sync_core_errors=$((sync_core_errors + 1))
  return 1
}

sync_core_stage_adopt_item() {
  local id="$1"
  local desired_meta="$2"
  local actual_meta="$3"
  local out_file base fallback

  sync_core_resolve_output_dir

  base="$(sync_core_stage_basename_for_item "$id" "$desired_meta" "$actual_meta")"
  out_file="$sync_core_resolved_output_dir/$base"

  if [[ -e $out_file ]]; then
    fallback="$(sync_core_stage_fallback_basename_for_item "$id" "$desired_meta" "$actual_meta")"
    out_file="$sync_core_resolved_output_dir/$fallback"
  fi

  if sync_adapter_export_actual "$id" "$out_file" "$desired_meta" "$actual_meta"; then
    sync_core_staged=$((sync_core_staged + 1))
    sync_core_log_action "staged-ok" "$id" "$out_file"
    return 0
  fi

  sync_core_log_action "staged-failed" "$id"
  sync_core_errors=$((sync_core_errors + 1))
  return 1
}

sync_core_adopt_in_place_item() {
  local id="$1"
  local status="$2"
  local desired_meta="$3"
  local actual_meta="$4"
  local destination=""
  local adopted_hash=""

  if [[ $status == "conflict" && $sync_core_force -eq 0 ]]; then
    sync_core_log_action "adopt-refused" "$id"
    sync_core_refused=$((sync_core_refused + 1))
    return 1
  fi

  destination="$(sync_core_inplace_destination_for_item "$id" "$desired_meta" "$actual_meta")"

  if sync_adapter_export_actual "$id" "$destination" "$desired_meta" "$actual_meta"; then
    adopted_hash="$(sync_core_compute_actual_hash "$id" "$actual_meta" || true)"
    if [[ -z $adopted_hash ]]; then
      sync_core_log_action "hash-failed" "$id"
      sync_core_errors=$((sync_core_errors + 1))
      return 1
    fi

    if ! sync_core_write_last_applied_hash "$id" "$adopted_hash"; then
      sync_core_log_action "state-write-failed" "$id"
      sync_core_errors=$((sync_core_errors + 1))
      return 1
    fi

    sync_core_adopted=$((sync_core_adopted + 1))
    sync_core_log_action "adopt-ok" "$id" "$destination"
    return 0
  fi

  sync_core_log_action "adopt-failed" "$id" "$destination"
  sync_core_errors=$((sync_core_errors + 1))
  return 1
}

sync_core_handle_status() {
  local id="$1"
  local status="$2"
  local desired_hash="$3"
  local actual_hash="$4"
  local last_hash="$5"
  local desired_meta="$6"
  local actual_meta="$7"

  case "$status" in
  in-sync)
    sync_core_in_sync=$((sync_core_in_sync + 1))
    ;;
  safe-update)
    sync_core_pending=$((sync_core_pending + 1))
    sync_core_log_status "$id" "$status" "$desired_meta" "$actual_meta" "$last_hash"

    if [[ $sync_core_mode == "apply" ]]; then
      sync_core_apply_item "$id" "$desired_meta" "$actual_meta" 0 || true
    fi
    ;;
  in-sync-untracked)
    sync_core_in_sync=$((sync_core_in_sync + 1))
    sync_core_untracked=$((sync_core_untracked + 1))
    sync_core_log_status "$id" "$status" "$desired_meta" "$actual_meta" "$last_hash"

    if [[ $sync_core_mode == "apply" ]]; then
      if [[ -n $actual_hash ]] && sync_core_write_last_applied_hash "$id" "$actual_hash"; then
        sync_core_log_action "state-write-missing-ok" "$id"
      else
        sync_core_log_action "state-write-missing-failed" "$id"
        sync_core_errors=$((sync_core_errors + 1))
      fi
    fi
    ;;
  state-stale)
    sync_core_in_sync=$((sync_core_in_sync + 1))
    sync_core_state_stale=$((sync_core_state_stale + 1))
    sync_core_log_status "$id" "$status" "$desired_meta" "$actual_meta" "$last_hash"

    if [[ $sync_core_mode == "apply" ]]; then
      if [[ -n $actual_hash ]] && sync_core_write_last_applied_hash "$id" "$actual_hash"; then
        sync_core_log_action "state-refresh-ok" "$id"
      else
        sync_core_log_action "state-refresh-failed" "$id"
        sync_core_errors=$((sync_core_errors + 1))
      fi
    fi
    ;;
  missing)
    sync_core_missing=$((sync_core_missing + 1))
    sync_core_log_status "$id" "$status" "$desired_meta" "$actual_meta" "$last_hash"

    if [[ $sync_core_mode == "apply" ]]; then
      sync_core_apply_item "$id" "$desired_meta" "$actual_meta" 0 || true
    fi
    ;;
  drift-untracked | drift-missing | drift-external | conflict)
    sync_core_drift=$((sync_core_drift + 1))
    [[ $status == "conflict" ]] && sync_core_conflicts=$((sync_core_conflicts + 1))
    [[ $status == "drift-missing" ]] && sync_core_drift_missing=$((sync_core_drift_missing + 1))

    sync_core_log_status "$id" "$status" "$desired_meta" "$actual_meta" "$last_hash"

    if [[ $sync_core_details -eq 1 ]] && _sync_core_has_function sync_adapter_print_details; then
      sync_adapter_print_details "$id" "$status" "$desired_hash" "$actual_hash" "$last_hash" "$desired_meta" "$actual_meta" || true
    fi

    if [[ $sync_core_show_diff -eq 1 && $status != "drift-missing" ]] && _sync_core_has_function sync_adapter_print_diff; then
      sync_adapter_print_diff "$id" "$status" "$desired_meta" "$actual_meta" || true
    fi

    if [[ $status != "drift-missing" ]]; then
      sync_core_adoptable_drift=$((sync_core_adoptable_drift + 1))
    fi

    if [[ $sync_core_mode == "adopt" ]]; then
      if [[ $status == "drift-missing" ]]; then
        return 0
      fi

      if [[ $sync_core_in_place -eq 0 ]]; then
        sync_core_stage_adopt_item "$id" "$desired_meta" "$actual_meta" || true
      else
        sync_core_adopt_in_place_item "$id" "$status" "$desired_meta" "$actual_meta" || true
      fi
    elif [[ $sync_core_mode == "apply" ]]; then
      if [[ $sync_core_force -eq 0 ]]; then
        sync_core_unresolved=$((sync_core_unresolved + 1))
      else
        sync_core_apply_item "$id" "$desired_meta" "$actual_meta" 1 || true
      fi
    fi
    ;;
  *)
    if sync_core_is_invalid_status "$status"; then
      sync_core_invalid=$((sync_core_invalid + 1))
      sync_core_log_action "invalid" "$id" "$status"
      [[ -n $last_hash ]] && log "  lastApplied: $last_hash"
    else
      sync_core_invalid=$((sync_core_invalid + 1))
      sync_core_log_action "unknown-status" "$id" "$status"
    fi
    ;;
  esac
}

sync_core_print_summary() {
  sync_adapter_print_summary
}

sync_core_exit_for_mode() {
  case "$sync_core_mode" in
  check)
    if [[ $sync_core_invalid -gt 0 || $sync_core_errors -gt 0 || $sync_core_drift -gt 0 || $sync_core_missing -gt 0 ]]; then
      return 1
    fi
    return 0
    ;;
  adopt)
    if [[ $sync_core_in_place -eq 0 ]]; then
      if [[ $sync_core_invalid -gt 0 || $sync_core_errors -gt 0 || $sync_core_missing -gt 0 || $sync_core_drift_missing -gt 0 ]]; then
        return 1
      fi
      return 0
    fi

    if [[ $sync_core_invalid -gt 0 || $sync_core_errors -gt 0 || $sync_core_missing -gt 0 || $sync_core_drift_missing -gt 0 || $sync_core_refused -gt 0 || $sync_core_adopted -lt $sync_core_adoptable_drift ]]; then
      return 1
    fi
    return 0
    ;;
  apply)
    if [[ $sync_core_invalid -gt 0 || $sync_core_errors -gt 0 || $sync_core_unresolved -gt 0 ]]; then
      return 1
    fi
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

sync_core_run_forget() {
  local line id desired_meta actual_meta

  sync_core_forgotten=0
  sync_core_missing_state=0
  sync_core_selected=0
  sync_core_invalid="${sync_core_forget_invalid_seed:-0}"

  while IFS= read -r line; do
    [[ -z $line ]] && continue
    IFS='|' read -r id desired_meta actual_meta <<<"$line"

    if ! sync_adapter_is_selected "$id" "$desired_meta" "$actual_meta"; then
      continue
    fi

    sync_core_selected=$((sync_core_selected + 1))

    if sync_core_forget_last_applied_hash "$id"; then
      sync_core_forgotten=$((sync_core_forgotten + 1))
      sync_core_log_action "forgot" "$id"
    else
      sync_core_missing_state=$((sync_core_missing_state + 1))
      sync_core_log_action "no-state" "$id"
    fi
  done < <(sync_adapter_list_items)

  if [[ $sync_core_selected -eq 0 ]]; then
    sync_adapter_on_no_selection
  fi

  sync_core_print_summary

  if [[ $sync_core_invalid -gt 0 ]]; then
    return 1
  fi

  return 0
}

sync_core_run_sync() {
  local line id desired_meta actual_meta status_line
  local status desired_hash actual_hash last_hash

  sync_core_checked=0
  sync_core_selected=0
  sync_core_in_sync=0
  sync_core_pending=0
  sync_core_state_stale=0
  sync_core_drift=0
  sync_core_drift_missing=0
  sync_core_conflicts=0
  sync_core_missing=0
  sync_core_untracked=0
  sync_core_invalid="${sync_core_invalid_seed:-0}"
  sync_core_errors=0
  sync_core_applied=0
  sync_core_staged=0
  sync_core_adopted=0
  sync_core_refused=0
  sync_core_adoptable_drift=0
  sync_core_unresolved=0
  sync_core_resolved_output_dir=""

  while IFS= read -r line; do
    [[ -z $line ]] && continue
    IFS='|' read -r id desired_meta actual_meta <<<"$line"

    if ! sync_adapter_is_selected "$id" "$desired_meta" "$actual_meta"; then
      continue
    fi

    sync_core_selected=$((sync_core_selected + 1))
    sync_core_checked=$((sync_core_checked + 1))

    status_line="$(sync_core_determine_item_status "$id" "$desired_meta" "$actual_meta")"
    IFS='|' read -r status _ desired_hash actual_hash last_hash desired_meta actual_meta <<<"$status_line"

    sync_core_handle_status "$id" "$status" "$desired_hash" "$actual_hash" "$last_hash" "$desired_meta" "$actual_meta"
  done < <(sync_adapter_list_items)

  if [[ $sync_core_selected -eq 0 ]]; then
    sync_adapter_on_no_selection
  fi

  sync_core_print_summary

  if [[ $sync_core_mode == "apply" ]] && _sync_core_has_function sync_adapter_after_apply; then
    if ! sync_adapter_after_apply; then
      sync_core_errors=$((sync_core_errors + 1))
    fi
  fi

  sync_core_exit_for_mode
}

sync_core_run() {
  sync_core_require_adapter

  case "$sync_core_mode" in
  forget)
    sync_core_run_forget
    ;;
  check | apply | adopt)
    sync_core_run_sync
    ;;
  *)
    die "unsupported mode: $sync_core_mode"
    ;;
  esac
}
