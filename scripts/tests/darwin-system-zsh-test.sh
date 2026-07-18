#!/usr/bin/env bash
set -euo pipefail

runtime_zsh="${DARWIN_SYSTEM_ZSH:?DARWIN_SYSTEM_ZSH must point to the managed zsh}"

if [[ $(uname -s) != Darwin ]]; then
  echo "FAIL: darwin-system-zsh test must run on Darwin" >&2
  exit 1
fi

if [[ ! -L $runtime_zsh ]]; then
  echo "FAIL: managed zsh is not a symlink: $runtime_zsh" >&2
  exit 1
fi

if [[ $(readlink "$runtime_zsh") != /bin/zsh ]]; then
  echo "FAIL: managed zsh must resolve directly to /bin/zsh" >&2
  exit 1
fi

path_helper_length="$(
  timeout -k 1 5 "$runtime_zsh" -dfc \
    'path_helper_output=$(/usr/libexec/path_helper -s); print -r -- ${#path_helper_output}'
)"

if [[ ! $path_helper_length =~ ^[1-9][0-9]*$ ]]; then
  echo "FAIL: system zsh did not complete a path_helper command substitution" >&2
  exit 1
fi

echo "PASS: Darwin system zsh runtime"
