#!/usr/bin/env bash

if [[ -n ${DOTFILES_LIB_LOADED:-} ]]; then
  return 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_SCRIPT_DIR="$SCRIPT_DIR"
LIB_PATH="$DOTFILES_SCRIPT_DIR/lib.sh"

if [[ ! -f $LIB_PATH ]]; then
  echo "${DOTFILES_SCRIPT_LABEL:-dotfiles}: lib.sh not found (tried $LIB_PATH)" >&2
  return 1
fi

# shellcheck source=lib.sh
source "$LIB_PATH"
export DOTFILES_SCRIPT_DIR

DOTFILES_LIB_LOADED=1
