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
  Runs a lightweight Doom Emacs config sync smoke test with a temporary HOME.
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
doom_dir="$home_dir/.config/doom"
emacs_dir="$home_dir/.emacs.d"
mkdir -p "$home_dir" "$managed_dir"

cat >"$managed_dir/init.el" <<'EOF_INIT'
;;; init.el -*- lexical-binding: t; -*-

(doom! :editor
       (meow +qwerty))
EOF_INIT

cat >"$managed_dir/packages.el" <<'EOF_PACKAGES'
;;; packages.el -*- no-byte-compile: t; -*-

(package! vundo)
EOF_PACKAGES

cat >"$managed_dir/config.el" <<'EOF_CONFIG'
;;; config.el -*- lexical-binding: t; -*-

(setq doom-theme 'doom-one)
EOF_CONFIG

run_emacs_sync() {
  HOME="$home_dir" bash "$SYNC_SCRIPT" emacs "$@" --config-only --managed-dir "$managed_dir" --doom-dir "$doom_dir" --emacs-dir "$emacs_dir"
}

run_emacs_sync_runtime() {
  HOME="$home_dir" bash "$SYNC_SCRIPT" emacs "$@" --managed-dir "$managed_dir" --doom-dir "$doom_dir" --emacs-dir "$emacs_dir"
}

run_emacs_sync_from_copy() {
  local copied_root="$tmp_root/scripts-copy"

  if [[ ! -d $copied_root ]]; then
    cp -R "$ROOT/scripts" "$copied_root"
    chmod -R u+w "$copied_root"
  fi

  HOME="$home_dir" bash "$copied_root/sync.sh" emacs "$@" --config-only --managed-dir "$managed_dir" --doom-dir "$doom_dir" --emacs-dir "$emacs_dir"
}

printf 'test: running Emacs sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if run_emacs_sync --check >/dev/null; then
  echo "FAIL: check unexpectedly passed before Doom config apply" >&2
  exit 1
fi

if ! run_emacs_sync --apply >/dev/null; then
  echo "FAIL: apply failed for missing Doom config" >&2
  exit 1
fi

for file in init.el packages.el config.el; do
  if [[ ! -f $doom_dir/$file || -L $doom_dir/$file ]]; then
    echo "FAIL: missing writable Doom config file after apply: $file" >&2
    exit 1
  fi
done

if run_emacs_sync_runtime --check >"$tmp_root/doom-missing.out" 2>"$tmp_root/doom-missing.err"; then
  echo "FAIL: runtime check unexpectedly passed without Doom checkout" >&2
  exit 1
fi

if ! grep -Fq "doom=missing" "$tmp_root/doom-missing.err"; then
  echo "FAIL: runtime check did not report missing Doom checkout" >&2
  cat "$tmp_root/doom-missing.err" >&2 || true
  exit 1
fi

if ! grep -Fq -- "--bootstrap" "$tmp_root/doom-missing.err"; then
  echo "FAIL: runtime missing guidance did not mention --bootstrap" >&2
  cat "$tmp_root/doom-missing.err" >&2 || true
  exit 1
fi

mkdir -p "$emacs_dir/bin"
cat >"$emacs_dir/bin/doom" <<'EOF_DOOM'
#!/usr/bin/env bash
exit 0
EOF_DOOM
chmod +x "$emacs_dir/bin/doom"

if ! run_emacs_sync_runtime --check >/dev/null; then
  echo "FAIL: runtime check failed with fake Doom executable" >&2
  exit 1
fi

if ! run_emacs_sync --check >/dev/null; then
  echo "FAIL: check after initial apply failed" >&2
  exit 1
fi

if ! run_emacs_sync_from_copy --check --item config.el >/dev/null; then
  echo "FAIL: check failed when sync script ran outside repo root with explicit dirs" >&2
  exit 1
fi

cat >"$doom_dir/config.el" <<'EOF_LOCAL_CONFIG'
;;; config.el -*- lexical-binding: t; -*-

(setq doom-theme 'modus-vivendi)
EOF_LOCAL_CONFIG

if run_emacs_sync --check --details --diff --item config >"$tmp_root/config-check.out" 2>"$tmp_root/config-check.err"; then
  echo "FAIL: check unexpectedly passed after Doom config drift" >&2
  exit 1
fi

if ! grep -Fq "details: config" "$tmp_root/config-check.err"; then
  echo "FAIL: details output missing for drifted config" >&2
  cat "$tmp_root/config-check.err" >&2 || true
  exit 1
fi

if ! grep -Fq "modus-vivendi" "$tmp_root/config-check.out"; then
  echo "FAIL: diff output missing local Doom config drift" >&2
  cat "$tmp_root/config-check.out" >&2 || true
  exit 1
fi

if ! run_emacs_sync --adopt --item config >/dev/null; then
  echo "FAIL: adopt failed for local Doom config drift" >&2
  exit 1
fi

if ! grep -Fq "modus-vivendi" "$managed_dir/config.el"; then
  echo "FAIL: adopt did not copy runtime config back to managed dir" >&2
  exit 1
fi

if ! run_emacs_sync --check --item config >/dev/null; then
  echo "FAIL: config check failed after adopt" >&2
  exit 1
fi

cat >"$managed_dir/packages.el" <<'EOF_PACKAGES_UPDATED'
;;; packages.el -*- no-byte-compile: t; -*-

(package! vundo)
(package! dirvish)
EOF_PACKAGES_UPDATED

if run_emacs_sync --check --item packages >/dev/null; then
  echo "FAIL: packages check unexpectedly passed after managed-dir update" >&2
  exit 1
fi

if ! run_emacs_sync --apply --item packages.el >/dev/null; then
  echo "FAIL: apply failed for managed packages update" >&2
  exit 1
fi

if ! grep -Fq "(package! dirvish)" "$doom_dir/packages.el"; then
  echo "FAIL: apply did not copy managed packages update to runtime" >&2
  exit 1
fi

linked_init="$tmp_root/linked-init.el"
cp "$managed_dir/init.el" "$linked_init"
rm -f "$doom_dir/init.el"
ln -s "$linked_init" "$doom_dir/init.el"

if run_emacs_sync --check --item init >/dev/null; then
  echo "FAIL: check unexpectedly accepted symlinked Doom init" >&2
  exit 1
fi

if ! run_emacs_sync --apply --item init >/dev/null; then
  echo "FAIL: apply failed to materialize symlinked Doom init" >&2
  exit 1
fi

if [[ -L $doom_dir/init.el ]]; then
  echo "FAIL: symlinked Doom init was not materialized" >&2
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
