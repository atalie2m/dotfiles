#!/usr/bin/env bash
# shellcheck disable=SC2034

# This helper intentionally updates TARGET_* globals that are consumed by the
# sync entrypoint and sibling sourced helpers.

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
    symlink-store | symlink-regular)
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
