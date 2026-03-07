#!/usr/bin/env bash

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
  print_unified_diff "$TARGET_DESIRED_TMP" "$TARGET_ACTUAL_TMP"
}
