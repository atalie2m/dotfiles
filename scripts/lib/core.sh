#!/usr/bin/env bash

script_label() {
  basename "${DOTFILES_SCRIPT_LABEL:-$0}"
}

log() {
  printf '%s: %s\n' "$(script_label)" "$*" >&2
}

die() {
  log "$*"
  exit 1
}
