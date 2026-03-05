#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VSCODE_SCRIPT="$ROOT/nix/scripts/vscode-instances.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/vscode-instances-smoke-test.sh

Description:
  Runs isolated smoke tests for nix/scripts/vscode-instances.sh using a fake
  code binary.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x $VSCODE_SCRIPT ]]; then
  echo "test: vscode script not executable: $VSCODE_SCRIPT" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "test: jq is required" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/vscode-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

base_dir="$tmp_root/instances"
name="smoke"
settings_json="$tmp_root/settings.json"
extensions_txt="$tmp_root/extensions.txt"
disabled_extensions_txt="$tmp_root/extensions-disabled.txt"
baseline_id="baseline-smoke-v1"
fake_code="$tmp_root/fake-code.sh"
installed_file="$tmp_root/installed.txt"
launch_log="$tmp_root/launch.log"

cat >"$settings_json" <<'EOF'
{
  "window.title": "Baseline Title",
  "window.titleSeparator": " :: ",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#111111",
    "titleBar.inactiveBackground": "#222222",
    "statusBar.background": "#333333",
    "statusBar.noFolderBackground": "#444444"
  },
  "editor.tabSize": 2
}
EOF

cat >"$extensions_txt" <<'EOF'
ext.one
ext.two
EOF

cat >"$disabled_extensions_txt" <<'EOF'
ext.disabled
EOF

cat >"$fake_code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

installed_file="${FAKE_CODE_INSTALLED_FILE:?}"
launch_log="${FAKE_CODE_LAUNCH_LOG:?}"

if [[ ${1:-} == "--user-data-dir" ]]; then
  :
fi

if [[ " $* " == *" --list-extensions "* ]]; then
  cat "$installed_file" 2>/dev/null || true
  exit 0
fi

if [[ " $* " == *" --install-extension "* ]]; then
  ext=""
  args=("$@")
  idx=0
  while [[ $idx -lt ${#args[@]} ]]; do
    if [[ ${args[$idx]} == "--install-extension" ]]; then
      idx=$((idx + 1))
      ext="${args[$idx]}"
      break
    fi
    idx=$((idx + 1))
  done
  [[ -n $ext ]] || exit 1
  grep -Fxq "$ext" "$installed_file" 2>/dev/null || echo "$ext" >>"$installed_file"
  exit 0
fi

printf '%s\n' "$*" >>"$launch_log"
exit 0
EOF
chmod +x "$fake_code"

run_vscode() {
  FAKE_CODE_INSTALLED_FILE="$installed_file" \
    FAKE_CODE_LAUNCH_LOG="$launch_log" \
    "$VSCODE_SCRIPT" "$@"
}

data_dir="$base_dir/$name/user-data"
user_settings="$data_dir/User/settings.json"
mkdir -p "$(dirname "$user_settings")"
cat >"$user_settings" <<'EOF'
{
  "window.title": "User Title Override",
  "editor.fontFamily": "FiraCode"
}
EOF

printf 'test: running vscode instances smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

run_vscode bootstrap \
  --name "$name" \
  --base-dir "$base_dir" \
  --code-bin "$fake_code" \
  --settings-json "$settings_json" \
  --extensions-txt "$extensions_txt" \
  --baseline-id "$baseline_id"

marker_file="$data_dir/.dotfiles-baseline"
if [[ ! -f $marker_file ]]; then
  echo "FAIL: marker file missing after bootstrap" >&2
  exit 1
fi

if [[ $(cat "$marker_file") != "$baseline_id" ]]; then
  echo "FAIL: marker file baseline mismatch" >&2
  exit 1
fi

if [[ $(jq -r '.["window.title"]' "$user_settings") != "Baseline Title" ]]; then
  echo "FAIL: bootstrap did not force baseline window.title" >&2
  exit 1
fi

if [[ $(jq -r '.["editor.fontFamily"]' "$user_settings") != "FiraCode" ]]; then
  echo "FAIL: bootstrap did not preserve user setting" >&2
  exit 1
fi

if ! grep -Fxq "ext.one" "$installed_file" || ! grep -Fxq "ext.two" "$installed_file"; then
  echo "FAIL: bootstrap did not install baseline extensions" >&2
  exit 1
fi

run_vscode launch \
  --name "$name" \
  --base-dir "$base_dir" \
  --code-bin "$fake_code" \
  --settings-json "$settings_json" \
  --extensions-txt "$extensions_txt" \
  --disabled-extensions-txt "$disabled_extensions_txt" \
  --baseline-id "$baseline_id" \
  -- /tmp/workspace

if ! grep -Fq -- "--disable-extension ext.disabled" "$launch_log"; then
  echo "FAIL: launch did not pass disabled extension args" >&2
  exit 1
fi

if ! grep -Fq -- "--new-window" "$launch_log"; then
  echo "FAIL: launch did not request a new window" >&2
  exit 1
fi

touch "$base_dir/$name/extra-file"
run_vscode reset \
  --name "$name" \
  --base-dir "$base_dir" \
  --code-bin "$fake_code" \
  --settings-json "$settings_json" \
  --extensions-txt "$extensions_txt" \
  --baseline-id "$baseline_id"

backup_count=$(find "$base_dir" -maxdepth 1 -type d -name "${name}.backup-*" | wc -l | tr -d '[:space:]')
if [[ $backup_count -lt 1 ]]; then
  echo "FAIL: reset did not create backup directory" >&2
  exit 1
fi

if [[ ! -f "$base_dir/$name/user-data/.dotfiles-baseline" ]]; then
  echo "FAIL: reset did not restore marker file" >&2
  exit 1
fi

echo "PASS: vscode instances smoke"
