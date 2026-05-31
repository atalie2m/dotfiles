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
qa_root="$tmp_root/work"
state_dir="$tmp_root/state"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT
mkdir -p "$state_dir"

qa_state_eval='
(let ((state-dir (file-name-as-directory (getenv "DOTFILES_EMACS_QA_STATE_DIR"))))
  (setq abbrev-file-name (expand-file-name "abbrev_defs" state-dir)
        auto-save-list-file-prefix (expand-file-name "auto-save-list/.saves-" state-dir)
        backup-directory-alist `(("." . ,(expand-file-name "backups/" state-dir)))
        bookmark-default-file (expand-file-name "bookmarks" state-dir)
        project-list-file (expand-file-name "projects" state-dir)
        recentf-save-file (expand-file-name "recentf" state-dir)
        savehist-file (expand-file-name "history" state-dir)
        save-place-file (expand-file-name "places" state-dir)
        tramp-persistency-file-name (expand-file-name "tramp" state-dir)
        transient-history-file (expand-file-name "transient/history.el" state-dir)
        transient-levels-file (expand-file-name "transient/levels.el" state-dir)
        transient-values-file (expand-file-name "transient/values.el" state-dir)
        url-configuration-directory (expand-file-name "url/" state-dir)))
'

printf 'test: running Emacs package QA\n'
printf 'test: temp root = %s\n' "$tmp_root"

DOTFILES_EMACS_QA_ROOT="$qa_root" \
  DOTFILES_EMACS_QA_STATE_DIR="$state_dir" \
  "$emacs_bin" --batch --debug-init \
  -l "$early_init" \
  --eval "$qa_state_eval" \
  -l "$init" \
  --eval "$qa_state_eval" \
  -l "$ROOT/scripts/tests/emacs-package-qa.el"

echo "PASS: Emacs package QA"
