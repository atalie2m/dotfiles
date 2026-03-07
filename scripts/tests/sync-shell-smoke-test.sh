#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/scripts/sync.sh"
MANAGED_DIR="$ROOT/surfaces/shell/desired"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/sync-shell-smoke-test.sh

Description:
  Runs a lightweight shell sync smoke test with a temporary HOME.
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

if [[ ! -d $MANAGED_DIR ]]; then
  echo "test: managed dir not found: $MANAGED_DIR" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shell-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
mkdir -p "$home_dir"

run_shell_sync() {
  HOME="$home_dir" bash "$SYNC_SCRIPT" shell "$@" --managed-dir "$MANAGED_DIR"
}

printf 'test: running shell sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: apply failed for missing bash entrypoint" >&2
  exit 1
fi

bash_rc="$home_dir/.bashrc"
if [[ ! -f $bash_rc || -L $bash_rc ]]; then
  echo "FAIL: missing writable bashrc after apply" >&2
  exit 1
fi

if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: check after initial apply failed" >&2
  exit 1
fi

tmp_mutated="$tmp_root/bashrc.mutated"
/usr/bin/awk '
  BEGIN { replaced = 0 }
  {
    if (replaced == 0) {
      gsub("\\.nix/hm-bash/\\.bashrc", ".nix/hm-bash/.bashrc.smoke")
      if ($0 ~ /\\.bashrc\\.smoke/) {
        replaced = 1
      }
    }
    print
  }
' "$bash_rc" >"$tmp_mutated"
mv "$tmp_mutated" "$bash_rc"

if run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: check unexpectedly passed after managed block drift" >&2
  exit 1
fi

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: apply failed to repair managed block drift" >&2
  exit 1
fi

if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: check failed after repair apply" >&2
  exit 1
fi

printf '\n# smoke tail\n' >>"$bash_rc"
if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: apply failed after adding unmanaged tail" >&2
  exit 1
fi

if ! grep -Fqx '# smoke tail' "$bash_rc"; then
  echo "FAIL: unmanaged tail was not preserved" >&2
  exit 1
fi

if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: final check failed" >&2
  exit 1
fi

if ! run_shell_sync --apply --group zsh >/dev/null; then
  echo "FAIL: apply failed for zsh entrypoint" >&2
  exit 1
fi

zsh_wrapper="$home_dir/.nix/.zshrc"
if [[ ! -f $zsh_wrapper || -L $zsh_wrapper ]]; then
  echo "FAIL: missing writable zsh wrapper after apply" >&2
  exit 1
fi

if ! grep -Fq '# >>> dotfiles-managed:zdotdir.zshrc >>>' "$zsh_wrapper"; then
  echo "FAIL: zsh wrapper is missing the managed block marker" >&2
  exit 1
fi

if ! run_shell_sync --check --group zsh >/dev/null; then
  echo "FAIL: zsh check failed after apply" >&2
  exit 1
fi

echo "PASS: shell sync smoke"
