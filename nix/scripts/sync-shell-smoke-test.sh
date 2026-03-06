#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
MANAGED_DIR="$ROOT/surfaces/shell/desired"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/sync-shell-smoke-test.sh

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

if ! run_shell_sync --apply --group fish >/dev/null; then
  echo "FAIL: apply failed for fish entrypoints" >&2
  exit 1
fi

fish_config="$home_dir/.config/fish/config.fish"
fish_core="$home_dir/.config/fish/conf.d/00-dotfiles.fish"
if [[ ! -f $fish_config || -L $fish_config ]]; then
  echo "FAIL: missing writable fish config after apply" >&2
  exit 1
fi

if [[ ! -f $fish_core || -L $fish_core ]]; then
  echo "FAIL: missing writable fish hook after apply" >&2
  exit 1
fi

if ! grep -Fq '$HOME/.config/fish/hm-fish/config.fish' "$fish_config"; then
  echo "FAIL: fish runtime wrapper does not source the immutable HM layer" >&2
  exit 1
fi

if ! grep -Fq '$HOME/.config/shell/fish.local.fish' "$fish_core"; then
  echo "FAIL: fish conf.d hook does not source the local extension point" >&2
  exit 1
fi

if ! run_shell_sync --check --group fish >/dev/null; then
  echo "FAIL: fish check failed after apply" >&2
  exit 1
fi

echo "PASS: shell sync smoke"
