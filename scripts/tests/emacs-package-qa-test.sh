#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/emacs-package-qa-test.sh

Description:
  Runs a live Emacs package QA harness against the configured Emacs directory.
  This intentionally uses the real Elpaca package state and writes only under a
  temporary QA root.

Environment:
  EMACS_BIN   Emacs executable to run. Defaults to `emacs`.
  EMACSDIR    Runtime Emacs config directory. Defaults to `$HOME/.emacs.d`.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z ${HOME:-} ]]; then
  echo "test: HOME is required" >&2
  exit 1
fi

emacs_bin="${EMACS_BIN:-emacs}"
emacs_dir="${EMACSDIR:-$HOME/.emacs.d}"
early_init="$emacs_dir/early-init.el"
init="$emacs_dir/init.el"

if ! command -v "$emacs_bin" >/dev/null 2>&1; then
  echo "test: Emacs executable not found: $emacs_bin" >&2
  exit 1
fi

for file in "$early_init" "$init"; do
  if [[ ! -f $file ]]; then
    echo "test: Emacs config file not found: $file" >&2
    echo "test: run sync emacs --apply before package QA" >&2
    exit 1
  fi
done

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/emacs-package-qa.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

printf 'test: running Emacs package QA\n'
printf 'test: temp root = %s\n' "$tmp_root"

DOTFILES_EMACS_QA_ROOT="$tmp_root" \
  "$emacs_bin" --batch --debug-init \
  -l "$early_init" \
  -l "$init" \
  -l "$ROOT/scripts/tests/emacs-package-qa.el"

echo "PASS: Emacs package QA"
