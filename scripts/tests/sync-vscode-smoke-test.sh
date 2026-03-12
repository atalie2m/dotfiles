#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/scripts/sync.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/sync-vscode-smoke-test.sh

Description:
  Runs a lightweight VS Code native profile sync smoke test with a temporary HOME.
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

if ! command -v jq >/dev/null 2>&1; then
  echo "test: jq is required" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "test: sqlite3 is required" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-vscode-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
managed_dir="$tmp_root/managed"
fake_bin_dir="$tmp_root/bin"
fake_code="$fake_bin_dir/code"
code_state_dir="$tmp_root/code-state"

mkdir -p "$home_dir" "$managed_dir/_default" "$managed_dir/native" "$managed_dir/web" "$fake_bin_dir" "$code_state_dir"
mkdir -p "$home_dir/.local/share/vscode-instances/native"
mkdir -p "$home_dir/.vscode/extensions/ext.base-1.0.0" "$home_dir/.vscode/extensions/ext.stale-1.0.0"

cat >"$home_dir/.vscode/extensions/extensions.json" <<'EOF'
[
  {
    "identifier": {
      "id": "ext.base"
    },
    "relativeLocation": "ext.base-1.0.0",
    "version": "1.0.0"
  }
]
EOF

cat >"$managed_dir/_default/settings.json" <<'EOF'
{
  "window.title": "[BASE] ${profileName}",
  "files.autoSave": "afterDelay",
  "editor.fontLigatures": true
}
EOF

cat >"$managed_dir/_default/extensions.txt" <<'EOF'
ext.base
EOF

cat >"$managed_dir/_default/default-disabled-extensions.txt" <<'EOF'
ext.base
EOF

cat >"$managed_dir/native/settings.json" <<'EOF'
{
  "workbench.colorTheme": "Catppuccin Frappé"
}
EOF

cat >"$managed_dir/native/extensions.txt" <<'EOF'
ext.native
EOF

cat >"$managed_dir/web/settings.json" <<'EOF'
{
  "window.title": "[WEB] ${profileName}",
  "workbench.colorTheme": "Abyss"
}
EOF

cat >"$managed_dir/web/extensions.txt" <<'EOF'
ext.web
EOF

cat >"$managed_dir/web/default-disabled-extensions.txt" <<'EOF'
ext.web
EOF

cat >"$fake_code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${FAKE_CODE_STATE_DIR:?}"
profile="native"
command=""
extension_id=""
extensions_root="${HOME}/.vscode/extensions"
extensions_manifest="${extensions_root}/extensions.json"

ensure_manifest() {
  mkdir -p "$extensions_root"
  if [[ ! -f $extensions_manifest ]]; then
    printf '[]\n' >"$extensions_manifest"
  fi
}

upsert_manifest_extension() {
  local ext="$1"
  local slug location tmp_file
  slug="${ext}-1.0.0"
  location="${extensions_root}/${slug}"
  mkdir -p "$location"
  ensure_manifest
  tmp_file="${extensions_manifest}.tmp"
  jq -S \
    --arg id "$ext" \
    --arg slug "$slug" \
    --arg path "$location" \
    '
      [ .[] | select((.identifier.id // "") != $id) ] + [
        {
          identifier: { id: $id },
          location: { "$mid": 1, path: $path, scheme: "file" },
          relativeLocation: $slug,
          version: "1.0.0"
        }
      ]
    ' "$extensions_manifest" >"$tmp_file"
  mv "$tmp_file" "$extensions_manifest"
}

remove_manifest_extension() {
  local ext="$1"
  local tmp_file
  ensure_manifest
  tmp_file="${extensions_manifest}.tmp"
  jq -S --arg id "$ext" '[ .[] | select((.identifier.id // "") != $id) ]' "$extensions_manifest" >"$tmp_file"
  mv "$tmp_file" "$extensions_manifest"
}

args=("$@")
idx=0
while [[ $idx -lt ${#args[@]} ]]; do
  case "${args[$idx]}" in
  --profile)
    idx=$((idx + 1))
    profile="${args[$idx]}"
    ;;
  --list-extensions)
    command="list"
    ;;
  --install-extension)
    command="install"
    idx=$((idx + 1))
    extension_id="${args[$idx]}"
    ;;
  --uninstall-extension)
    command="uninstall"
    idx=$((idx + 1))
    extension_id="${args[$idx]}"
    ;;
  --force)
    ;;
  esac
  idx=$((idx + 1))
done

profile_slug=$(printf '%s' "$profile" | tr ' /' '__')
profile_file="$state_dir/${profile_slug}.extensions"
touch "$profile_file"

case "$command" in
list)
  awk 'NF { print }' "$profile_file"
  ;;
install)
  upsert_manifest_extension "$extension_id"
  awk -v ext="$extension_id" '
    BEGIN { seen = 0 }
    $0 == ext { seen = 1 }
    { print }
    END {
      if (seen == 0) {
        print ext
      }
    }
  ' "$profile_file" >"${profile_file}.tmp"
  mv "${profile_file}.tmp" "$profile_file"
  ;;
uninstall)
  remove_manifest_extension "$extension_id"
  awk -v ext="$extension_id" '$0 != ext { print }' "$profile_file" >"${profile_file}.tmp"
  mv "${profile_file}.tmp" "$profile_file"
  ;;
*)
  echo "fake code: unsupported args: $*" >&2
  exit 1
  ;;
esac
EOF
chmod +x "$fake_code"

run_vscode_sync() {
  HOME="$home_dir" \
    PATH="$fake_bin_dir:$PATH" \
    FAKE_CODE_STATE_DIR="$code_state_dir" \
    bash "$SYNC_SCRIPT" vscode "$@" --managed-dir "$managed_dir"
}

run_vscode_sync_from_copy() {
  local copied_root="$tmp_root/scripts-copy"

  if [[ ! -d $copied_root ]]; then
    cp -R "$ROOT/scripts" "$copied_root"
    chmod -R u+w "$copied_root"
  fi

  HOME="$home_dir" \
    PATH="$fake_bin_dir:$PATH" \
    FAKE_CODE_STATE_DIR="$code_state_dir" \
    bash "$copied_root/sync.sh" vscode "$@" --managed-dir "$managed_dir"
}

web_profile_id() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf 'dotfiles:vscode-profile:web' | sha256sum | awk '{ print substr($1, 1, 32) }'
    return 0
  fi

  printf 'dotfiles:vscode-profile:web' | shasum -a 256 | awk '{ print substr($1, 1, 32) }'
}

native_profile_id() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf 'dotfiles:vscode-profile:native' | sha256sum | awk '{ print substr($1, 1, 32) }'
    return 0
  fi

  printf 'dotfiles:vscode-profile:native' | shasum -a 256 | awk '{ print substr($1, 1, 32) }'
}

printf 'test: running VS Code sync smoke test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_vscode_sync --apply >/dev/null; then
  echo "FAIL: initial VS Code apply failed" >&2
  exit 1
fi

web_id="$(web_profile_id)"
native_id="$(native_profile_id)"
storage_json="$home_dir/Library/Application Support/Code/User/globalStorage/storage.json"
native_settings="$home_dir/Library/Application Support/Code/User/profiles/$native_id/settings.json"
web_settings="$home_dir/Library/Application Support/Code/User/profiles/$web_id/settings.json"
native_profile_extensions="$home_dir/Library/Application Support/Code/User/profiles/$native_id/extensions.json"
native_state="$home_dir/.local/state/dotfiles/vscode/native.json"
web_state="$home_dir/.local/state/dotfiles/vscode/web.json"
native_db="$home_dir/Library/Application Support/Code/User/profiles/$native_id/globalStorage/state.vscdb"
web_db="$home_dir/Library/Application Support/Code/User/profiles/$web_id/globalStorage/state.vscdb"

if [[ ! -f $storage_json ]]; then
  echo "FAIL: storage.json was not created" >&2
  exit 1
fi

if ! jq -e --arg id "$web_id" '.userDataProfiles | any(.[]; .name == "Web" and .location == $id)' "$storage_json" >/dev/null; then
  echo "FAIL: web profile was not registered in storage.json" >&2
  exit 1
fi

if ! jq -e --arg id "$native_id" '.userDataProfiles | any(.[]; .name == "Native" and .location == $id)' "$storage_json" >/dev/null; then
  echo "FAIL: native profile was not registered in storage.json" >&2
  exit 1
fi

if [[ ! -f $native_settings ]]; then
  echo "FAIL: native settings were not written" >&2
  exit 1
fi

if [[ ! -f $web_settings ]]; then
  echo "FAIL: web settings were not written" >&2
  exit 1
fi

if [[ $(jq -r '.["files.autoSave"]' "$web_settings") != "afterDelay" ]]; then
  echo "FAIL: shared settings were not merged into web profile" >&2
  exit 1
fi

if [[ $(jq -r '.["workbench.colorTheme"]' "$native_settings") != "Catppuccin Frappé" ]]; then
  echo "FAIL: native settings overlay was not applied" >&2
  exit 1
fi

if [[ ! -f $native_state || ! -f $web_state ]]; then
  echo "FAIL: state files were not created" >&2
  exit 1
fi

if [[ ! -f $native_db || ! -f $web_db ]]; then
  echo "FAIL: enablement databases were not created" >&2
  exit 1
fi

if ! jq -e '.ownedSettingsKeys | index("files.autoSave")' "$web_state" >/dev/null; then
  echo "FAIL: web state file does not track owned settings" >&2
  exit 1
fi

if ! jq -e '.bootstrappedDefaultDisabledExtensions | index("ext.base")' "$native_state" >/dev/null; then
  echo "FAIL: native state file does not track bootstrapped default-disabled extensions" >&2
  exit 1
fi

if ! jq -e '.bootstrappedDefaultDisabledExtensions | index("ext.base") and index("ext.web")' "$web_state" >/dev/null; then
  echo "FAIL: web state file does not track bootstrapped default-disabled extensions" >&2
  exit 1
fi

if ! jq -e 'any(.[]; .identifier.id == "ext.base") and any(.[]; .identifier.id == "ext.native")' "$native_profile_extensions" >/dev/null; then
  echo "FAIL: native extensions were not recorded in the profile manifest" >&2
  exit 1
fi

if ! jq -e 'any(.[]; .identifier.id == "ext.base") and any(.[]; .identifier.id == "ext.web")' "$home_dir/Library/Application Support/Code/User/profiles/$web_id/extensions.json" >/dev/null; then
  echo "FAIL: web extensions were not written to the profile manifest" >&2
  exit 1
fi

if [[ -d "$home_dir/.local/share/vscode-instances" ]]; then
  echo "FAIL: legacy vscode instances directory was not removed" >&2
  exit 1
fi

if [[ -d "$home_dir/.vscode/extensions/ext.stale-1.0.0" ]]; then
  echo "FAIL: orphaned VS Code extension dir was not removed" >&2
  exit 1
fi

native_disabled_json="$(sqlite3 "$native_db" "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';")"
web_disabled_json="$(sqlite3 "$web_db" "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';")"

if ! printf '%s' "$native_disabled_json" | jq -e 'map(.id) | index("ext.base")' >/dev/null; then
  echo "FAIL: native default-disabled extension was not bootstrapped into enablement storage" >&2
  exit 1
fi

if ! printf '%s' "$web_disabled_json" | jq -e 'map(.id) | index("ext.base") and index("ext.web")' >/dev/null; then
  echo "FAIL: web default-disabled extensions were not bootstrapped into enablement storage" >&2
  exit 1
fi

jq '. + { "editor.minimap.enabled": false }' "$web_settings" >"$tmp_root/web-settings-user.json"
mv "$tmp_root/web-settings-user.json" "$web_settings"
jq '. + [{ "identifier": { "id": "ext.user" }, "relativeLocation": "ext.user-1.0.0", "location": { "$mid": 1, "path": "'"$home_dir"'/.vscode/extensions/ext.user-1.0.0", "scheme": "file" }, "version": "1.0.0" }]' \
  "$home_dir/Library/Application Support/Code/User/profiles/$web_id/extensions.json" >"$tmp_root/web-extensions-user.json"
mv "$tmp_root/web-extensions-user.json" "$home_dir/Library/Application Support/Code/User/profiles/$web_id/extensions.json"
mkdir -p "$home_dir/.vscode/extensions/ext.user-1.0.0"
jq '. + [{ "identifier": { "id": "ext.user" }, "relativeLocation": "ext.user-1.0.0", "location": { "$mid": 1, "path": "'"$home_dir"'/.vscode/extensions/ext.user-1.0.0", "scheme": "file" }, "version": "1.0.0" }]' \
  "$home_dir/.vscode/extensions/extensions.json" >"$tmp_root/global-extensions-user.json"
mv "$tmp_root/global-extensions-user.json" "$home_dir/.vscode/extensions/extensions.json"
sqlite3 "$web_db" "INSERT INTO ItemTable(key, value) VALUES ('extensionsIdentifiers/disabled', '[]') ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
sqlite3 "$web_db" "INSERT INTO ItemTable(key, value) VALUES ('extensionsIdentifiers/enabled', '[{\"id\":\"ext.base\"},{\"id\":\"ext.web\"}]') ON CONFLICT(key) DO UPDATE SET value = excluded.value;"

cat >"$managed_dir/_default/settings.json" <<'EOF'
{
  "window.title": "[BASE] ${profileName}",
  "editor.fontLigatures": true
}
EOF

cat >"$managed_dir/web/extensions.txt" <<'EOF'
EOF

cat >"$managed_dir/web/default-disabled-extensions.txt" <<'EOF'
EOF

if ! run_vscode_sync --apply >/dev/null; then
  echo "FAIL: second VS Code apply failed" >&2
  exit 1
fi

if jq -e 'has("files.autoSave")' "$web_settings" >/dev/null; then
  echo "FAIL: removed owned settings key still exists after apply" >&2
  exit 1
fi

if [[ $(jq -r '.["editor.minimap.enabled"]' "$web_settings") != "false" ]]; then
  echo "FAIL: unmanaged user setting was not preserved" >&2
  exit 1
fi

if jq -e 'any(.[]; .identifier.id == "ext.web")' "$home_dir/Library/Application Support/Code/User/profiles/$web_id/extensions.json" >/dev/null; then
  echo "FAIL: removed owned extension still exists in the web profile manifest after apply" >&2
  exit 1
fi

if ! jq -e 'any(.[]; .identifier.id == "ext.user")' "$home_dir/Library/Application Support/Code/User/profiles/$web_id/extensions.json" >/dev/null; then
  echo "FAIL: unmanaged user extension was not preserved in the web profile manifest" >&2
  exit 1
fi

web_disabled_json="$(sqlite3 "$web_db" "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';")"
if ! printf '%s' "$web_disabled_json" | jq -e 'map(.id) | length == 0' >/dev/null; then
  echo "FAIL: manually re-enabled default-disabled extension was bootstrapped again on apply" >&2
  exit 1
fi

if ! jq -e '.bootstrappedDefaultDisabledExtensions | index("ext.base") and (index("ext.web") | not)' "$web_state" >/dev/null; then
  echo "FAIL: web state file did not refresh bootstrapped default-disabled extensions after apply" >&2
  exit 1
fi

rm -rf "$home_dir/.vscode/extensions/ext.native-1.0.0"
if run_vscode_sync --check >/dev/null; then
  echo "FAIL: check did not detect missing extension payload directory" >&2
  exit 1
fi

if ! run_vscode_sync --apply >/dev/null; then
  echo "FAIL: apply did not recover missing extension payload directory" >&2
  exit 1
fi

if [[ ! -d "$home_dir/.vscode/extensions/ext.native-1.0.0" ]]; then
  echo "FAIL: missing extension payload directory was not restored" >&2
  exit 1
fi

sqlite3 "$web_db" "DELETE FROM ItemTable WHERE key IN ('extensionsIdentifiers/disabled', 'extensionsIdentifiers/enabled');"
if ! run_vscode_sync --apply >/dev/null; then
  echo "FAIL: apply did not reseed default-disabled extensions after enablement DB reset" >&2
  exit 1
fi

web_disabled_json="$(sqlite3 "$web_db" "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';")"
if ! printf '%s' "$web_disabled_json" | jq -e 'map(.id) | index("ext.base")' >/dev/null; then
  echo "FAIL: default-disabled extensions were not re-seeded when enablement DB keys were missing" >&2
  exit 1
fi

if ! run_vscode_sync --check >/dev/null; then
  echo "FAIL: final VS Code check failed" >&2
  exit 1
fi

if ! run_vscode_sync_from_copy --check >/dev/null; then
  echo "FAIL: VS Code check failed when sync script ran outside repo root with explicit managed dir" >&2
  exit 1
fi

echo "PASS: VS Code sync smoke"
