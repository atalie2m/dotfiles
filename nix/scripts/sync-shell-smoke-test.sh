#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
SOURCE_MANAGED_DIR="$ROOT/surfaces/shell/desired"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/sync-shell-smoke-test.sh

Description:
  Runs a lightweight shell sync smoke test with temporary HOME/XDG_STATE_HOME
  and a temporary managed-dir copy.
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

if [[ ! -d $SOURCE_MANAGED_DIR ]]; then
  echo "test: managed dir not found: $SOURCE_MANAGED_DIR" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shell-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
state_dir="$tmp_root/state"
managed_dir="$tmp_root/managed"
mkdir -p "$home_dir" "$state_dir"
cp -R "$SOURCE_MANAGED_DIR" "$managed_dir"
chmod -R u+w "$managed_dir"

run_shell_sync() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$state_dir" \
    bash "$SYNC_SCRIPT" shell "$@" \
    --managed-dir "$managed_dir" \
    --state-dir "$state_dir/blocks"
}

printf 'test: running shell sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: apply unexpectedly succeeded before migrate" >&2
  exit 1
fi

if ! run_shell_sync --migrate --item bash-rc >/dev/null; then
  echo "FAIL: migrate failed for missing bash entrypoint" >&2
  exit 1
fi

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: apply failed after migrate" >&2
  exit 1
fi

if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: check after apply failed" >&2
  exit 1
fi

bash_rc="$home_dir/.bashrc"
if [[ ! -f $bash_rc ]]; then
  echo "FAIL: missing bashrc after apply" >&2
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
  echo "FAIL: check unexpectedly passed after drift" >&2
  exit 1
fi

if ! run_shell_sync --adopt --in-place --item bash-rc >/dev/null; then
  echo "FAIL: in-place adopt failed" >&2
  exit 1
fi

if ! grep -Fq '.nix/hm-bash/.bashrc.smoke' "$managed_dir/bashrc.entrypoint.block.sh"; then
  echo "FAIL: adopt did not update managed desired file" >&2
  exit 1
fi

if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: final check failed after adopt" >&2
  exit 1
fi

echo "PASS: shell sync smoke"
