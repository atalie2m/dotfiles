#!/usr/bin/env bash

apply_target() {
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
