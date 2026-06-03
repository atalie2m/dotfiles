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

run_shell_sync_from_copy() {
  local copied_root="$tmp_root/scripts-copy"

  if [[ ! -d $copied_root ]]; then
    cp -R "$ROOT/scripts" "$copied_root"
    chmod -R u+w "$copied_root"
  fi

  HOME="$home_dir" bash "$copied_root/sync.sh" shell "$@" --managed-dir "$MANAGED_DIR"
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

if ! run_shell_sync_from_copy --check --item bash-rc >/dev/null; then
  echo "FAIL: check failed when sync script ran outside repo root with explicit managed dir" >&2
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

materialized_source="$tmp_root/bashrc.source"
cat >"$materialized_source" <<'EOF_SOURCE'
# source content
export BASH_SOURCE_MARKER=1
EOF_SOURCE
rm -f "$bash_rc"
ln -s "$materialized_source" "$bash_rc"

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: apply failed to materialize non-store symlink" >&2
  exit 1
fi

if [[ ! -f $bash_rc || -L $bash_rc ]]; then
  echo "FAIL: bashrc was not materialized into a writable regular file" >&2
  exit 1
fi

if ! grep -Fqx 'export BASH_SOURCE_MARKER=1' "$bash_rc"; then
  echo "FAIL: materialized symlink content was not preserved" >&2
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

rm -rf "$home_dir/.nix"
printf 'not a directory\n' >"$home_dir/.nix"
if run_shell_sync --apply --item zsh-zdotdir >"$tmp_root/zsh-apply-failure.out" 2>"$tmp_root/zsh-apply-failure.err"; then
  echo "FAIL: apply unexpectedly succeeded when the zsh wrapper parent path was a file" >&2
  exit 1
fi

if ! grep -Fq "apply failed for 'zsh-zdotdir': failed to create $home_dir/.nix" "$tmp_root/zsh-apply-failure.err"; then
  echo "FAIL: shell sync did not report the root-cause apply error" >&2
  cat "$tmp_root/zsh-apply-failure.err" >&2 || true
  exit 1
fi

mkdir -p "$home_dir/.nix-profile/bin" "$home_dir/.nix-profile/etc/profile.d"
cat >"$home_dir/.nix-profile/bin/fallback-profile-tool" <<'EOF_FALLBACK_PROFILE_TOOL'
#!/usr/bin/env bash
printf 'fallback profile tool\n'
EOF_FALLBACK_PROFILE_TOOL
chmod +x "$home_dir/.nix-profile/bin/fallback-profile-tool"

cat >"$home_dir/.nix-profile/etc/profile.d/hm-session-vars.sh" <<'EOF_HM_SESSION_VARS'
# test fixture
export PATH="$HOME/.local/bin${PATH:+:}$PATH"
EOF_HM_SESSION_VARS

common_path_output="$tmp_root/common.path"
if ! env -i \
  HOME="$home_dir" \
  USER=shellsmoke \
  LOGNAME=shellsmoke \
  PATH="$PATH" \
  bash -lc "source \"$ROOT/apps/shell/common.sh\" && command -v fallback-profile-tool && printf 'PATH=%s\n' \"\$PATH\"" >"$common_path_output"; then
  echo "FAIL: sourcing common.sh failed" >&2
  exit 1
fi

if ! grep -Fqx "$home_dir/.nix-profile/bin/fallback-profile-tool" "$common_path_output"; then
  echo "FAIL: common.sh did not expose fallback profile bins" >&2
  cat "$common_path_output" >&2 || true
  exit 1
fi

if ! grep -Fq "$home_dir/.local/bin" "$common_path_output"; then
  echo "FAIL: common.sh did not source hm-session-vars.sh" >&2
  cat "$common_path_output" >&2 || true
  exit 1
fi

echo "PASS: shell sync smoke"
