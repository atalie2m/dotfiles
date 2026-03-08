#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VSCODE_SCRIPT="$ROOT/scripts/vscode.sh"
DOTFILES_SCRIPT="$ROOT/scripts/dotfiles.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/vscode-launch-test.sh

Description:
  Runs a lightweight VS Code launch helper test with a fake code binary.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f $VSCODE_SCRIPT || ! -f $DOTFILES_SCRIPT ]]; then
  echo "test: vscode launch scripts not found" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/vscode-launch.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

managed_dir="$tmp_root/managed"
fake_bin="$tmp_root/bin"
printed_command="$tmp_root/printed-command.txt"
mkdir -p "$managed_dir/_default" "$managed_dir/native" "$managed_dir/web" "$fake_bin"

cat >"$managed_dir/_default/launch-disabled-extensions.txt" <<'EOF'
shared.one
shared.two
EOF

cat >"$managed_dir/web/launch-disabled-extensions.txt" <<'EOF'
web.only
shared.two
EOF

cat >"$fake_bin/code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${FAKE_CODE_ARGS_FILE:?}"
EOF
chmod +x "$fake_bin/code"

run_vscode_launch() {
  PATH="$fake_bin:$PATH" \
    FAKE_CODE_ARGS_FILE="$tmp_root/code.args" \
    VSCODE_DATA_HOME="$tmp_root/vscode-data" \
    bash "$VSCODE_SCRIPT" launch --managed-dir "$managed_dir" "$@"
}

run_vscode_launch_from_copy() {
  local copied_root="$tmp_root/scripts-copy"

  if [[ ! -d $copied_root ]]; then
    cp -R "$ROOT/scripts" "$copied_root"
    chmod -R u+w "$copied_root"
  fi

  PATH="$fake_bin:$PATH" \
    FAKE_CODE_ARGS_FILE="$tmp_root/code-copy.args" \
    VSCODE_DATA_HOME="$tmp_root/vscode-data" \
    bash "$copied_root/dotfiles.sh" vscode launch --managed-dir "$managed_dir" "$@"
}

printf 'test: running VS Code launch helper test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_vscode_launch --profile web -- foo bar >/dev/null; then
  echo "FAIL: web launch failed" >&2
  exit 1
fi

if ! grep -Fqx -- "--user-data-dir" "$tmp_root/code.args"; then
  echo "FAIL: launch did not pass --user-data-dir" >&2
  cat "$tmp_root/code.args" >&2 || true
  exit 1
fi

if ! grep -Fqx -- "--profile" "$tmp_root/code.args" || ! grep -Fqx -- "Web" "$tmp_root/code.args"; then
  echo "FAIL: launch did not pass the expected profile name" >&2
  cat "$tmp_root/code.args" >&2 || true
  exit 1
fi

for extension_id in shared.one shared.two web.only; do
  if ! grep -Fqx -- "$extension_id" "$tmp_root/code.args"; then
    echo "FAIL: launch missing disabled extension $extension_id" >&2
    cat "$tmp_root/code.args" >&2 || true
    exit 1
  fi
done

if [[ $(grep -Fxc -- "shared.two" "$tmp_root/code.args") != "1" ]]; then
  echo "FAIL: duplicate disabled extension was not de-duplicated" >&2
  cat "$tmp_root/code.args" >&2 || true
  exit 1
fi

if ! tail -n 2 "$tmp_root/code.args" | grep -Fqx "foo" || ! tail -n 1 "$tmp_root/code.args" | grep -Fqx "bar"; then
  echo "FAIL: launch did not forward trailing code args" >&2
  cat "$tmp_root/code.args" >&2 || true
  exit 1
fi

if ! run_vscode_launch --profile native >/dev/null; then
  echo "FAIL: native launch failed" >&2
  exit 1
fi

if grep -Fqx -- "--profile" "$tmp_root/code.args"; then
  echo "FAIL: native launch unexpectedly passed --profile" >&2
  cat "$tmp_root/code.args" >&2 || true
  exit 1
fi

if ! run_vscode_launch_from_copy --profile web --print-command >"$printed_command"; then
  echo "FAIL: dotfiles vscode launch from copied scripts failed" >&2
  exit 1
fi

if ! grep -Fq -- "--disable-extension" "$printed_command" || ! grep -Fq -- "web.only" "$printed_command"; then
  echo "FAIL: printed command did not include launch-disabled extensions" >&2
  cat "$printed_command" >&2 || true
  exit 1
fi

echo "PASS: VS Code launch helper"
