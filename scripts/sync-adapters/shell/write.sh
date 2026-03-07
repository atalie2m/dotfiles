#!/usr/bin/env bash

write_managed_block_file() {
  local output_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"

  printf '%s\n' "$begin_marker" >"$output_file"
  append_canonicalized_text_to_file "$desired_file" "$output_file"
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
          append_canonicalized_text_to_file "$target_file" "$tmp_out"
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
