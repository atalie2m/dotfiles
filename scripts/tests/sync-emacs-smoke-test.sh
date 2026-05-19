#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/scripts/sync.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/sync-emacs-smoke-test.sh

Description:
  Runs a lightweight Emacs config sync smoke test with a temporary HOME.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-emacs-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
managed_dir="$tmp_root/managed"
emacs_dir="$home_dir/.emacs.d"
mkdir -p "$home_dir" "$managed_dir"

cat >"$managed_dir/early-init.el" <<'EOF_EARLY_INIT'
;;; early-init.el -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)
EOF_EARLY_INIT

cat >"$managed_dir/init.el" <<'EOF_INIT'
;;; init.el -*- lexical-binding: t; -*-

(setq dotfiles-emacs-ready t)
EOF_INIT

run_emacs_sync() {
  HOME="$home_dir" bash "$SYNC_SCRIPT" emacs "$@" --managed-dir "$managed_dir" --emacs-dir "$emacs_dir"
}

run_emacs_sync_from_copy() {
  local copied_root="$tmp_root/scripts-copy"

  if [[ ! -d $copied_root ]]; then
    cp -R "$ROOT/scripts" "$copied_root"
    chmod -R u+w "$copied_root"
  fi

  HOME="$home_dir" bash "$copied_root/sync.sh" emacs "$@" --managed-dir "$managed_dir" --emacs-dir "$emacs_dir"
}

printf 'test: running Emacs sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if run_emacs_sync --check >/dev/null; then
  echo "FAIL: check unexpectedly passed before Emacs config apply" >&2
  exit 1
fi

if ! run_emacs_sync --apply >/dev/null; then
  echo "FAIL: apply failed for missing Emacs config" >&2
  exit 1
fi

for file in early-init.el init.el; do
  if [[ ! -f $emacs_dir/$file || -L $emacs_dir/$file ]]; then
    echo "FAIL: missing writable Emacs config file after apply: $file" >&2
    exit 1
  fi
done

if ! run_emacs_sync --check >/dev/null; then
  echo "FAIL: check after initial apply failed" >&2
  exit 1
fi

if ! run_emacs_sync_from_copy --check --item init.el >/dev/null; then
  echo "FAIL: check failed when sync script ran outside repo root with explicit dirs" >&2
  exit 1
fi

cat >"$emacs_dir/init.el" <<'EOF_LOCAL_INIT'
;;; init.el -*- lexical-binding: t; -*-

(setq dotfiles-emacs-ready nil)
EOF_LOCAL_INIT

if run_emacs_sync --check --details --diff --item init >"$tmp_root/init-check.out" 2>"$tmp_root/init-check.err"; then
  echo "FAIL: check unexpectedly passed after Emacs config drift" >&2
  exit 1
fi

if ! grep -Fq "details: init" "$tmp_root/init-check.err"; then
  echo "FAIL: details output missing for drifted config" >&2
  cat "$tmp_root/init-check.err" >&2 || true
  exit 1
fi

if ! grep -Fq "dotfiles-emacs-ready nil" "$tmp_root/init-check.out"; then
  echo "FAIL: diff output missing local Emacs config drift" >&2
  cat "$tmp_root/init-check.out" >&2 || true
  exit 1
fi

if ! run_emacs_sync --adopt --item init >/dev/null; then
  echo "FAIL: adopt failed for local Emacs config drift" >&2
  exit 1
fi

if ! grep -Fq "dotfiles-emacs-ready nil" "$managed_dir/init.el"; then
  echo "FAIL: adopt did not copy runtime config back to managed dir" >&2
  exit 1
fi

if ! run_emacs_sync --check --item init >/dev/null; then
  echo "FAIL: init check failed after adopt" >&2
  exit 1
fi

cat >"$managed_dir/early-init.el" <<'EOF_EARLY_UPDATED'
;;; early-init.el -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)
(setq frame-inhibit-implied-resize t)
EOF_EARLY_UPDATED

if run_emacs_sync --check --item early-init >/dev/null; then
  echo "FAIL: early-init check unexpectedly passed after managed-dir update" >&2
  exit 1
fi

if ! run_emacs_sync --apply --item early-init.el >/dev/null; then
  echo "FAIL: apply failed for managed early-init update" >&2
  exit 1
fi

if ! grep -Fq "frame-inhibit-implied-resize" "$emacs_dir/early-init.el"; then
  echo "FAIL: apply did not copy managed early-init update to runtime" >&2
  exit 1
fi

linked_init="$tmp_root/linked-init.el"
cp "$managed_dir/init.el" "$linked_init"
rm -f "$emacs_dir/init.el"
ln -s "$linked_init" "$emacs_dir/init.el"

if run_emacs_sync --check --item init >/dev/null; then
  echo "FAIL: check unexpectedly accepted symlinked Emacs init" >&2
  exit 1
fi

if ! run_emacs_sync --apply --item init >/dev/null; then
  echo "FAIL: apply failed to materialize symlinked Emacs init" >&2
  exit 1
fi

if [[ -L $emacs_dir/init.el ]]; then
  echo "FAIL: symlinked Emacs init was not materialized" >&2
  exit 1
fi

missing_item="missing-emacs-item"
if run_emacs_sync --check --item "$missing_item" >/dev/null 2>"$tmp_root/missing-item.err"; then
  echo "FAIL: Emacs sync unexpectedly accepted missing --item" >&2
  exit 1
fi

if ! grep -Fq "no item matched --item '$missing_item'" "$tmp_root/missing-item.err"; then
  echo "FAIL: Emacs sync missing-item message changed" >&2
  cat "$tmp_root/missing-item.err" >&2 || true
  exit 1
fi

if ! run_emacs_sync --check >/dev/null; then
  echo "FAIL: final Emacs sync check failed" >&2
  exit 1
fi

echo "PASS: Emacs sync smoke"
