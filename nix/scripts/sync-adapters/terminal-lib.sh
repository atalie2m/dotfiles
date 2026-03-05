#!/usr/bin/env bash

profile_state_key() {
  local name="$1"
  local short_hash prefix

  short_hash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1, 1, 12)}')"
  prefix="$(printf '%s' "$name" | /usr/bin/tr '[:space:]' '-' | /usr/bin/tr -cd '[:alnum:]._-')"
  [[ -z $prefix ]] && prefix="profile"

  printf '%s.%s\n' "$prefix" "$short_hash"
}
