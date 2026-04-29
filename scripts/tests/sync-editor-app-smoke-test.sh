#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOTFILES_BIN="${DOTFILES_BIN:-dotfiles}"
DOTFILES_SYNC_APP="${DOTFILES_SYNC_APP:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/sync-editor-app-smoke-test.sh

Description:
  Verifies the nix app wrapper that runs Emacs and Neovim sync together.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z $DOTFILES_SYNC_APP || ! -x $DOTFILES_SYNC_APP ]]; then
  echo "test: DOTFILES_SYNC_APP must point to the generated sync app" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-editor-app-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
doom_dir="$home_dir/.config/doom"
emacs_dir="$home_dir/.emacs.d"
nvim_dir="$home_dir/.config/nvim"
mkdir -p "$home_dir"

run_with_home() {
  HOME="$home_dir" DOTFILES_ROOT="$ROOT" "$@"
}

printf 'test: running editor sync app smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_with_home "$DOTFILES_BIN" sync emacs --apply --config-only >/dev/null; then
  echo "FAIL: failed to prime Doom config runtime" >&2
  exit 1
fi

mkdir -p "$emacs_dir/bin"
cat >"$emacs_dir/bin/doom" <<'EOF_DOOM'
#!/usr/bin/env bash
exit 0
EOF_DOOM
chmod +x "$emacs_dir/bin/doom"

if ! run_with_home "$DOTFILES_BIN" sync neovim --apply >/dev/null; then
  echo "FAIL: failed to prime Neovim runtime" >&2
  exit 1
fi

if ! run_with_home "$DOTFILES_SYNC_APP" --check >"$tmp_root/check.out" 2>"$tmp_root/check.err"; then
  echo "FAIL: editor sync app check failed after priming runtimes" >&2
  cat "$tmp_root/check.err" >&2 || true
  exit 1
fi

if [[ $(grep -Fc "dotfiles: running sync " "$tmp_root/check.err") -ne 2 ]]; then
  echo "FAIL: editor sync app did not log both sync surfaces" >&2
  cat "$tmp_root/check.err" >&2 || true
  exit 1
fi

for surface in emacs neovim; do
  if ! grep -Fq "dotfiles: running sync $surface" "$tmp_root/check.err"; then
    echo "FAIL: editor sync app missing $surface log line" >&2
    cat "$tmp_root/check.err" >&2 || true
    exit 1
  fi
done

printf '\n;; wrapper smoke drift\n' >>"$doom_dir/config.el"
printf '\n-- wrapper smoke drift\n' >>"$nvim_dir/init.lua"

if run_with_home "$DOTFILES_SYNC_APP" --check >"$tmp_root/drift.out" 2>"$tmp_root/drift.err"; then
  echo "FAIL: editor sync app check unexpectedly passed after editor drift" >&2
  exit 1
fi

for surface in emacs neovim; do
  if ! grep -Fq "dotfiles: running sync $surface" "$tmp_root/drift.err"; then
    echo "FAIL: editor sync app stopped before running $surface check" >&2
    cat "$tmp_root/drift.err" >&2 || true
    exit 1
  fi
done

if [[ $(grep -Fc "summary: checked=" "$tmp_root/drift.err") -ne 2 ]]; then
  echo "FAIL: editor sync app did not report both summaries after drift" >&2
  cat "$tmp_root/drift.err" >&2 || true
  exit 1
fi

echo "PASS: editor sync app smoke"
