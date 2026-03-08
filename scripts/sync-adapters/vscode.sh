#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="sync-vscode"
ADAPTER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$ADAPTER_DIR/../lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- sync vscode --check [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- sync vscode --apply [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]

Description:
  Keep repo-managed VS Code native profiles aligned with repo-managed settings
  and extensions while preserving unmanaged drift outside the owned subset.

Options:
  --check              Report in-sync / needs-apply / missing / invalid (default mode)
  --apply              Reconcile managed settings, extensions, and profile registry state
  --details            Print concise per-profile details
  --diff               Print projected settings diff and extension add/remove lists
  --profile <name>     Restrict to one managed profile dir name (repeatable)
  --managed-dir <path> Profile definitions directory (default: <repo>/apps/vscode)
  --state-dir <path>   Owned-subset state directory (default: ${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode)
  --help               Show this help
USAGE
}

managed_dir=""
state_dir=""
mode="check"
mode_explicit=0
details=0
diff_output=0
profile_filters=""

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sync-vscode.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

new_tmp_file() {
  mktemp "$tmp_dir/file.XXXXXX"
}

append_profile_filter() {
  local profile_name="$1"

  if [[ -z $profile_filters ]]; then
    profile_filters="$profile_name"
    return 0
  fi

  case ",$profile_filters," in
  *",$profile_name,"*) ;;
  *)
    profile_filters="$profile_filters,$profile_name"
    ;;
  esac
}

set_mode() {
  local next_mode="$1"

  if [[ $mode_explicit -eq 1 && $mode != "$next_mode" ]]; then
    die "choose only one of --check or --apply"
  fi

  mode="$next_mode"
  mode_explicit=1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    set_mode "check"
    shift
    ;;
  --apply)
    set_mode "apply"
    shift
    ;;
  --details)
    details=1
    shift
    ;;
  --diff)
    diff_output=1
    shift
    ;;
  --profile)
    [[ $# -lt 2 ]] && die "missing value for --profile"
    append_profile_filter "$2"
    shift 2
    ;;
  --managed-dir)
    [[ $# -lt 2 ]] && die "missing value for --managed-dir"
    managed_dir="$2"
    shift 2
    ;;
  --state-dir)
    [[ $# -lt 2 ]] && die "missing value for --state-dir"
    state_dir="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    die "unknown option for sync vscode: $1"
    ;;
  esac
done

if [[ -z $managed_dir ]]; then
  set_repo_root
  managed_dir="$ROOT/apps/vscode"
fi

if [[ -z $state_dir ]]; then
  state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode"
fi

[[ -d $managed_dir ]] || die "managed dir not found: $managed_dir"
[[ -d $managed_dir/_default ]] || die "managed default profile dir not found: $managed_dir/_default"

code_bin="${VSCODE_CODE_BIN:-$(command -v code 2>/dev/null || true)}"
[[ -n $code_bin ]] || die "VS Code CLI not found in PATH (expected 'code')"
command -v jq >/dev/null 2>&1 || die "jq is required for sync vscode"

vscode_data_home="${VSCODE_DATA_HOME:-$HOME/Library/Application Support/Code}"
user_data_home="$vscode_data_home/User"
profiles_home="$user_data_home/profiles"
global_storage_dir="$user_data_home/globalStorage"
storage_json_path="$global_storage_dir/storage.json"
extensions_root="${VSCODE_EXTENSIONS_DIR:-$HOME/.vscode/extensions}"
extensions_manifest_path="$extensions_root/extensions.json"
legacy_instances_dir="${VSCODE_LEGACY_INSTANCES_DIR:-$HOME/.local/share/vscode-instances}"
code_cli_retries="${VSCODE_CODE_RETRIES:-3}"

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{ print $1 }'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{ print $1 }'
    return 0
  fi

  die "required command not found in PATH: sha256sum or shasum"
}

run_code_cli() {
  local stdout_file stderr_file attempt rc

  stdout_file="$(new_tmp_file)"
  stderr_file="$(new_tmp_file)"
  attempt=1

  while true; do
    if "$@" >"$stdout_file" 2>"$stderr_file"; then
      cat "$stdout_file"
      if [[ -s $stderr_file ]]; then
        cat "$stderr_file" >&2
      fi
      return 0
    fi

    rc=$?

    if [[ $attempt -lt $code_cli_retries ]] && grep -Eq 'FATAL ERROR: v8::ToLocalChecked Empty MaybeLocal|Abort trap: 6' "$stderr_file"; then
      log "VS Code CLI crashed; retrying (${attempt}/${code_cli_retries})"
      attempt=$((attempt + 1))
      sleep 1
      continue
    fi

    cat "$stdout_file"
    cat "$stderr_file" >&2
    return "$rc"
  done
}

prune_orphaned_extension_dirs() {
  local keep_file path path_name

  [[ -d $extensions_root ]] || return 0
  [[ -f $extensions_manifest_path ]] || return 0

  keep_file="$(new_tmp_file)"
  jq -r '.[] | .relativeLocation // empty' "$extensions_manifest_path" | awk 'NF { print }' >"$keep_file"

  shopt -s nullglob
  for path in "$extensions_root"/*; do
    [[ -d $path ]] || continue
    path_name="$(basename "$path")"
    if grep -Fqx "$path_name" "$keep_file"; then
      continue
    fi
    log "Removing orphaned VS Code extension dir: $path"
    rm -rf "$path"
  done
  shopt -u nullglob
}

profile_selected() {
  local profile_name="$1"

  if [[ -z $profile_filters ]]; then
    return 0
  fi

  case ",$profile_filters," in
  *",$profile_name,"*) return 0 ;;
  *) return 1 ;;
  esac
}

profile_display_name() {
  local profile_dir_name="$1"

  if [[ $profile_dir_name == "native" ]]; then
    printf 'Default\n'
    return 0
  fi

  printf '%s\n' "$profile_dir_name" | awk '
    BEGIN { FS = "[-_]+" }
    {
      out = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "") {
          continue
        }
        word = tolower($i)
        word = toupper(substr(word, 1, 1)) substr(word, 2)
        out = (out == "" ? word : out " " word)
      }
      print out
    }
  '
}

profile_id() {
  local profile_dir_name="$1"

  if [[ $profile_dir_name == "native" ]]; then
    printf '__default__profile__\n'
    return 0
  fi

  sha256_hex "dotfiles:vscode-profile:${profile_dir_name}" | awk '{ print substr($1, 1, 32) }'
}

profile_state_file() {
  local profile_dir_name="$1"
  printf '%s/%s.json\n' "$state_dir" "$profile_dir_name"
}

profile_runtime_dir() {
  local profile_dir_name="$1"
  printf '%s/%s\n' "$profiles_home" "$(profile_id "$profile_dir_name")"
}

profile_settings_path() {
  local profile_dir_name="$1"

  if [[ $profile_dir_name == "native" ]]; then
    printf '%s/settings.json\n' "$user_data_home"
  else
    printf '%s/settings.json\n' "$(profile_runtime_dir "$profile_dir_name")"
  fi
}

profile_extensions_manifest_path() {
  local profile_dir_name="$1"

  if [[ $profile_dir_name == "native" ]]; then
    printf '\n'
  else
    printf '%s/extensions.json\n' "$(profile_runtime_dir "$profile_dir_name")"
  fi
}

profile_disabled_file_path() {
  local profile_dir_name="$1"
  printf '%s/%s/extensions-disabled.txt\n' "$managed_dir" "$profile_dir_name"
}

lines_file_to_json_array() {
  local lines_file="$1"
  jq -Rs 'split("\n") | map(select(length > 0))' "$lines_file"
}

filter_extensions_file() {
  local input_path="$1"
  local output_path="$2"

  if [[ ! -f $input_path ]]; then
    : >"$output_path"
    return 0
  fi

  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 != "") {
        print $0
      }
    }
  ' "$input_path" >"$output_path"
}

build_desired_extensions() {
  local profile_dir_name="$1"
  local output_path="$2"
  local default_exts profile_exts combined

  default_exts="$(new_tmp_file)"
  profile_exts="$(new_tmp_file)"
  combined="$(new_tmp_file)"

  filter_extensions_file "$managed_dir/_default/extensions.txt" "$default_exts"
  filter_extensions_file "$managed_dir/$profile_dir_name/extensions.txt" "$profile_exts"

  cat "$default_exts" "$profile_exts" >"$combined"
  awk '!seen[$0]++' "$combined" >"$output_path"
}

build_desired_settings() {
  local profile_dir_name="$1"
  local output_path="$2"
  local default_settings profile_settings

  default_settings="$managed_dir/_default/settings.json"
  profile_settings="$managed_dir/$profile_dir_name/settings.json"

  if [[ ! -f $default_settings && ! -f $profile_settings ]]; then
    printf '{}\n' >"$output_path"
    return 0
  fi

  if [[ ! -f $default_settings && -f $profile_settings ]]; then
    jq -S '.' "$profile_settings" >"$output_path"
  elif [[ -f $profile_settings ]]; then
    jq -S -s '.[0] * .[1]' "$default_settings" "$profile_settings" >"$output_path"
  else
    jq -S '.' "$default_settings" >"$output_path"
  fi
}

state_file_valid() {
  local state_file="$1"
  local profile_dir_name="$2"
  local profile_name="$3"

  jq -e \
    --arg dir "$profile_dir_name" \
    --arg name "$profile_name" \
    '
      type == "object"
      and .version == 1
      and .profileDirName == $dir
      and .profileName == $name
      and (.ownedSettingsKeys | type == "array")
      and (.ownedExtensions | type == "array")
    ' "$state_file" >/dev/null
}

load_state_lists() {
  local state_file="$1"
  local profile_dir_name="$2"
  local profile_name="$3"
  local owned_keys_file="$4"
  local owned_extensions_file="$5"

  if [[ ! -f $state_file ]]; then
    : >"$owned_keys_file"
    : >"$owned_extensions_file"
    return 1
  fi

  if ! state_file_valid "$state_file" "$profile_dir_name" "$profile_name"; then
    return 2
  fi

  jq -r '.ownedSettingsKeys[]' "$state_file" >"$owned_keys_file"
  jq -r '.ownedExtensions[]' "$state_file" >"$owned_extensions_file"
  return 0
}

write_state_file() {
  local state_file="$1"
  local profile_dir_name="$2"
  local profile_name="$3"
  local owned_keys_file="$4"
  local owned_extensions_file="$5"
  local tmp_file

  tmp_file="$(new_tmp_file)"
  mkdir -p "$(dirname "$state_file")"

  jq -n \
    --arg dir "$profile_dir_name" \
    --arg name "$profile_name" \
    --argjson ownedKeys "$(lines_file_to_json_array "$owned_keys_file")" \
    --argjson ownedExtensions "$(lines_file_to_json_array "$owned_extensions_file")" \
    '
      {
        version: 1,
        profileDirName: $dir,
        profileName: $name,
        ownedSettingsKeys: $ownedKeys,
        ownedExtensions: $ownedExtensions
      }
    ' >"$tmp_file"

  mv "$tmp_file" "$state_file"
}

project_settings_subset() {
  local input_json="$1"
  local keys_file="$2"
  local output_json="$3"

  jq -S \
    --argjson keys "$(lines_file_to_json_array "$keys_file")" \
    '
      . as $src
      | reduce $keys[] as $key
          ({};
           if ($src | has($key)) then
             . + { ($key): $src[$key] }
           else
             .
           end)
    ' "$input_json" >"$output_json"
}

custom_profile_entry_matches_expected() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local profile_location="$3"

  [[ -f $storage_json_path ]] || return 1

  jq -e \
    --arg name "$profile_name" \
    --arg location "$profile_location" \
    '
      (.userDataProfiles // [])
      | any(.[]; .name == $name and .location == $location)
    ' "$storage_json_path" >/dev/null
}

ensure_storage_json_exists() {
  local tmp_file

  mkdir -p "$global_storage_dir"
  if [[ -f $storage_json_path ]]; then
    jq -S '.' "$storage_json_path" >/dev/null
    return 0
  fi

  tmp_file="$(new_tmp_file)"
  printf '{}\n' >"$tmp_file"
  mv "$tmp_file" "$storage_json_path"
}

ensure_custom_profile_registry() {
  local profile_name="$1"
  local profile_location="$2"
  local tmp_file

  ensure_storage_json_exists
  tmp_file="$(new_tmp_file)"

  jq -S \
    --arg name "$profile_name" \
    --arg location "$profile_location" \
    '
      .userDataProfiles =
        (
          (.userDataProfiles // [])
          | reduce .[] as $profile
              ([]; if ($profile.name == $name or $profile.location == $location) then . else . + [$profile] end)
          + [{ name: $name, location: $location }]
        )
    ' "$storage_json_path" >"$tmp_file"

  mv "$tmp_file" "$storage_json_path"
}

ensure_custom_profile_runtime() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local profile_location profile_dir settings_path extensions_manifest

  profile_location="$(profile_id "$profile_dir_name")"
  profile_dir="$(profile_runtime_dir "$profile_dir_name")"
  settings_path="$(profile_settings_path "$profile_dir_name")"
  extensions_manifest="$(profile_extensions_manifest_path "$profile_dir_name")"

  ensure_custom_profile_registry "$profile_name" "$profile_location"
  mkdir -p "$profile_dir"

  if [[ ! -f $settings_path ]]; then
    printf '{}\n' >"$settings_path"
  else
    jq -S '.' "$settings_path" >/dev/null
  fi

  if [[ -n $extensions_manifest ]]; then
    if [[ ! -f $extensions_manifest ]]; then
      printf '[]\n' >"$extensions_manifest"
    else
      jq -S '.' "$extensions_manifest" >/dev/null
    fi
    normalize_custom_profile_extension_manifest "$profile_dir_name" "$profile_name"
  fi
}

ensure_profile_runtime() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local settings_path extensions_manifest

  mkdir -p "$user_data_home"

  if [[ $profile_dir_name == "native" ]]; then
    settings_path="$(profile_settings_path "$profile_dir_name")"
    extensions_manifest="$extensions_manifest_path"
    if [[ ! -f $settings_path ]]; then
      printf '{}\n' >"$settings_path"
    else
      jq -S '.' "$settings_path" >/dev/null
    fi
    mkdir -p "$(dirname "$extensions_manifest")"
    if [[ ! -f $extensions_manifest ]]; then
      printf '[]\n' >"$extensions_manifest"
    else
      jq -S '.' "$extensions_manifest" >/dev/null
    fi
    prune_orphaned_extension_dirs
    return 0
  fi

  prune_orphaned_extension_dirs
  ensure_custom_profile_runtime "$profile_dir_name" "$profile_name"
}

list_profile_extensions() {
  local profile_dir_name="$1"
  local _profile_name="$2"
  local output_file="$3"
  local manifest_path

  if [[ $profile_dir_name == "native" ]]; then
    manifest_path="$extensions_manifest_path"
  else
    manifest_path="$(profile_extensions_manifest_path "$profile_dir_name")"
  fi

  if [[ ! -f $manifest_path ]]; then
    : >"$output_file"
    return 0
  fi

  jq -r '.[].identifier.id // empty' "$manifest_path" | awk 'NF { print }' | LC_ALL=C sort -u >"$output_file"
}

global_extension_manifest_entry() {
  local extension_id="$1"
  local output_file="$2"

  [[ -f $extensions_manifest_path ]] || return 1

  jq -e \
    --arg id "${extension_id,,}" \
    '
      map(select((.identifier.id // "" | ascii_downcase) == $id))
      | last
    ' "$extensions_manifest_path" >"$output_file"
}

normalize_custom_profile_extension_manifest() {
  local profile_dir_name="$1"
  local manifest_path ids_file rebuilt_file extension_id entry_file path

  manifest_path="$(profile_extensions_manifest_path "$profile_dir_name")"
  [[ -n $manifest_path ]] || return 0
  [[ -f $manifest_path ]] || return 0

  ids_file="$(new_tmp_file)"
  rebuilt_file="$(new_tmp_file)"
  printf '[]\n' >"$rebuilt_file"

  jq -r '.[].identifier.id // empty' "$manifest_path" | awk 'NF && !seen[$0]++ { print }' >"$ids_file"

  while IFS= read -r extension_id; do
    [[ -n $extension_id ]] || continue

    entry_file="$(new_tmp_file)"
    if ! global_extension_manifest_entry "$extension_id" "$entry_file"; then
      jq -e \
        --arg id "${extension_id,,}" \
        '
          map(select((.identifier.id // "" | ascii_downcase) == $id))
          | last
        ' "$manifest_path" >"$entry_file" || continue

      path="$(jq -r '.location.path // empty' "$entry_file")"
      if [[ -z $path || ! -e $path ]]; then
        continue
      fi
    fi

    jq -S --slurpfile entry "$entry_file" '. + [$entry[0]]' "$rebuilt_file" >"${rebuilt_file}.tmp"
    mv "${rebuilt_file}.tmp" "$rebuilt_file"
  done <"$ids_file"

  mv "$rebuilt_file" "$manifest_path"
}

add_custom_profile_extension_membership() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local extension_id="$3"
  local manifest_path manifest_entry tmp_file

  manifest_path="$(profile_extensions_manifest_path "$profile_dir_name")"
  [[ -n $manifest_path ]] || return 1

  ensure_custom_profile_runtime "$profile_dir_name" "$profile_name"

  manifest_entry="$(new_tmp_file)"
  if ! global_extension_manifest_entry "$extension_id" "$manifest_entry"; then
    return 1
  fi

  tmp_file="$(new_tmp_file)"
  jq -S \
    --slurpfile entry "$manifest_entry" \
    --arg id "${extension_id,,}" \
    '
      [ .[] | select((.identifier.id // "" | ascii_downcase) != $id) ] + [$entry[0]]
    ' "$manifest_path" >"$tmp_file"
  mv "$tmp_file" "$manifest_path"
}

remove_custom_profile_extension_membership() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local extension_id="$3"
  local manifest_path tmp_file

  manifest_path="$(profile_extensions_manifest_path "$profile_dir_name")"
  [[ -n $manifest_path ]] || return 1

  ensure_custom_profile_runtime "$profile_dir_name" "$profile_name"

  tmp_file="$(new_tmp_file)"
  jq -S \
    --arg id "${extension_id,,}" \
    '
      [ .[] | select((.identifier.id // "" | ascii_downcase) != $id) ]
    ' "$manifest_path" >"$tmp_file"
  mv "$tmp_file" "$manifest_path"
}

install_profile_extension() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local extension_id="$3"

  prune_orphaned_extension_dirs

  if [[ $profile_dir_name == "native" ]]; then
    run_code_cli "$code_bin" --user-data-dir "$vscode_data_home" --install-extension "$extension_id" --force
  else
    if add_custom_profile_extension_membership "$profile_dir_name" "$profile_name" "$extension_id"; then
      return 0
    fi

    if run_code_cli "$code_bin" --user-data-dir "$vscode_data_home" --install-extension "$extension_id" --force; then
      add_custom_profile_extension_membership "$profile_dir_name" "$profile_name" "$extension_id"
      return 0
    fi

    return 1
  fi
}

uninstall_profile_extension() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local extension_id="$3"

  prune_orphaned_extension_dirs

  if [[ $profile_dir_name == "native" ]]; then
    run_code_cli "$code_bin" --user-data-dir "$vscode_data_home" --uninstall-extension "$extension_id"
  else
    remove_custom_profile_extension_membership "$profile_dir_name" "$profile_name" "$extension_id"
  fi
}

all_desired_keys_match() {
  local actual_json="$1"
  local desired_json="$2"
  local desired_keys_file="$3"

  jq -e \
    --slurpfile desired "$desired_json" \
    --argjson keys "$(lines_file_to_json_array "$desired_keys_file")" \
    '
      . as $actual
      | ($desired[0]) as $wanted
      | all($keys[]; . as $key | ($actual | has($key)) and ($actual[$key] == $wanted[$key]))
    ' "$actual_json" >/dev/null
}

file_minus_file() {
  local left_file="$1"
  local right_file="$2"
  local output_file="$3"

  if [[ ! -s $left_file ]]; then
    : >"$output_file"
    return 0
  fi

  if [[ ! -s $right_file ]]; then
    cp "$left_file" "$output_file"
    return 0
  fi

  grep -Fvx -f "$right_file" "$left_file" >"$output_file" || true
}

file_intersection() {
  local left_file="$1"
  local right_file="$2"
  local output_file="$3"

  if [[ ! -s $left_file || ! -s $right_file ]]; then
    : >"$output_file"
    return 0
  fi

  grep -Fxf "$left_file" "$right_file" >"$output_file" || true
}

unique_lines_into_file() {
  local output_file="$1"
  shift

  awk '!seen[$0]++' "$@" >"$output_file"
}

line_count() {
  local input_file="$1"
  awk 'NF { count++ } END { print count + 0 }' "$input_file"
}

write_json_atomically() {
  local source_json="$1"
  local target_json="$2"
  local tmp_file

  tmp_file="$(new_tmp_file)"
  mkdir -p "$(dirname "$target_json")"
  jq -S '.' "$source_json" >"$tmp_file"
  mv "$tmp_file" "$target_json"
}

apply_settings_owned_subset() {
  local actual_json="$1"
  local desired_json="$2"
  local desired_keys_file="$3"
  local stale_keys_file="$4"
  local output_json="$5"

  jq -S \
    --slurpfile desired "$desired_json" \
    --argjson desiredKeys "$(lines_file_to_json_array "$desired_keys_file")" \
    --argjson staleKeys "$(lines_file_to_json_array "$stale_keys_file")" \
    '
      . as $actual
      | ($desired[0]) as $wanted
      | reduce $staleKeys[] as $key ($actual; del(.[$key]))
      | reduce $desiredKeys[] as $key (.;
          .[$key] = $wanted[$key])
    ' "$actual_json" >"$output_json"
}

profile_details() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local settings_path="$3"
  local state_file="$4"

  log "details: $profile_dir_name"
  log "  profile-name: $profile_name"
  log "  status: $PROFILE_STATUS"
  log "  settings: $settings_path"
  log "  state: $state_file"
  log "  reason: $PROFILE_REASON"
}

profile_diff() {
  local profile_dir_name="$1"

  log "diff: $profile_dir_name"
  if [[ -n ${PROFILE_SETTINGS_DIFF_EXPECTED:-} && -n ${PROFILE_SETTINGS_DIFF_ACTUAL:-} ]]; then
    print_unified_diff "$PROFILE_SETTINGS_DIFF_EXPECTED" "$PROFILE_SETTINGS_DIFF_ACTUAL"
  fi

  if [[ -n ${PROFILE_EXTENSIONS_ADD_FILE:-} && $(line_count "$PROFILE_EXTENSIONS_ADD_FILE") -gt 0 ]]; then
    log "  extensions-add:"
    awk '{ printf "  + %s\n", $0 }' "$PROFILE_EXTENSIONS_ADD_FILE" >&2
  fi

  if [[ -n ${PROFILE_EXTENSIONS_REMOVE_FILE:-} && $(line_count "$PROFILE_EXTENSIONS_REMOVE_FILE") -gt 0 ]]; then
    log "  extensions-remove:"
    awk '{ printf "  - %s\n", $0 }' "$PROFILE_EXTENSIONS_REMOVE_FILE" >&2
  fi
}

classify_profile() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local desired_settings="$3"
  local desired_extensions="$4"
  local state_file="$5"
  local settings_path="$6"
  local extensions_manifest="$7"
  local owned_keys_file="$8"
  local owned_extensions_file="$9"
  local actual_settings tmp_file state_rc desired_keys stale_keys stale_keys_present combined_keys
  local actual_extensions stale_extensions desired_missing stale_installed

  PROFILE_STATUS=""
  PROFILE_REASON=""
  PROFILE_SETTINGS_DIFF_EXPECTED=""
  PROFILE_SETTINGS_DIFF_ACTUAL=""
  PROFILE_EXTENSIONS_ADD_FILE=""
  PROFILE_EXTENSIONS_REMOVE_FILE=""

  if [[ -f $managed_dir/_default/extensions-disabled.txt ]]; then
    PROFILE_STATUS="invalid"
    PROFILE_REASON="apps/vscode/_default/extensions-disabled.txt is no longer supported"
    return 0
  fi

  if [[ -f $(profile_disabled_file_path "$profile_dir_name") ]]; then
    PROFILE_STATUS="invalid"
    PROFILE_REASON="apps/vscode/${profile_dir_name}/extensions-disabled.txt is no longer supported"
    return 0
  fi

  actual_settings="$(new_tmp_file)"
  desired_keys="$(new_tmp_file)"
  stale_keys="$(new_tmp_file)"
  stale_keys_present="$(new_tmp_file)"
  combined_keys="$(new_tmp_file)"
  actual_extensions="$(new_tmp_file)"
  stale_extensions="$(new_tmp_file)"
  desired_missing="$(new_tmp_file)"
  stale_installed="$(new_tmp_file)"

  state_rc=0
  if ! load_state_lists "$state_file" "$profile_dir_name" "$profile_name" "$owned_keys_file" "$owned_extensions_file"; then
    state_rc=$?
  fi

  if [[ $state_rc -eq 2 ]]; then
    PROFILE_STATUS="invalid"
    PROFILE_REASON="state file is malformed"
    return 0
  fi

  jq -r 'keys_unsorted[]' "$desired_settings" >"$desired_keys"
  file_minus_file "$owned_keys_file" "$desired_keys" "$stale_keys"
  file_minus_file "$owned_extensions_file" "$desired_extensions" "$stale_extensions"

  if [[ $profile_dir_name == "native" ]]; then
    if [[ ! -f $settings_path ]]; then
      PROFILE_STATUS="missing"
      PROFILE_REASON="native profile settings file is missing"
      return 0
    fi
  else
    if [[ ! -f $storage_json_path ]]; then
      PROFILE_STATUS="missing"
      PROFILE_REASON="VS Code profile registry is missing"
      return 0
    fi

    if ! jq -S '.' "$storage_json_path" >/dev/null; then
      PROFILE_STATUS="invalid"
      PROFILE_REASON="VS Code profile registry is not valid JSON"
      return 0
    fi

    if ! custom_profile_entry_matches_expected "$profile_dir_name" "$profile_name" "$(profile_id "$profile_dir_name")"; then
      PROFILE_STATUS="missing"
      PROFILE_REASON="managed profile is not registered at the expected native profile location"
      return 0
    fi

    if [[ ! -d $(profile_runtime_dir "$profile_dir_name") ]]; then
      PROFILE_STATUS="missing"
      PROFILE_REASON="managed profile directory is missing"
      return 0
    fi

    if [[ ! -f $settings_path ]]; then
      PROFILE_STATUS="missing"
      PROFILE_REASON="managed profile settings file is missing"
      return 0
    fi

    if [[ -n $extensions_manifest && ! -f $extensions_manifest ]]; then
      PROFILE_STATUS="missing"
      PROFILE_REASON="managed profile extensions manifest is missing"
      return 0
    fi
  fi

  if ! jq -S '.' "$settings_path" >"$actual_settings"; then
    PROFILE_STATUS="invalid"
    PROFILE_REASON="settings file is not valid JSON"
    return 0
  fi

  if ! list_profile_extensions "$profile_dir_name" "$profile_name" "$actual_extensions"; then
    PROFILE_STATUS="invalid"
    PROFILE_REASON="failed to inspect installed extensions"
    return 0
  fi

  file_intersection "$stale_extensions" "$actual_extensions" "$stale_installed"
  file_minus_file "$desired_extensions" "$actual_extensions" "$desired_missing"

  jq -r \
    --argjson keys "$(lines_file_to_json_array "$stale_keys")" \
    '
      . as $src
      | $keys[] as $key
      | select($src | has($key))
      | $key
    ' "$actual_settings" >"$stale_keys_present"

  unique_lines_into_file "$combined_keys" "$desired_keys" "$stale_keys_present"
  PROFILE_SETTINGS_DIFF_EXPECTED="$(new_tmp_file)"
  PROFILE_SETTINGS_DIFF_ACTUAL="$(new_tmp_file)"
  project_settings_subset "$desired_settings" "$desired_keys" "$PROFILE_SETTINGS_DIFF_EXPECTED"
  project_settings_subset "$actual_settings" "$combined_keys" "$PROFILE_SETTINGS_DIFF_ACTUAL"
  PROFILE_EXTENSIONS_ADD_FILE="$desired_missing"
  PROFILE_EXTENSIONS_REMOVE_FILE="$stale_installed"

  if [[ $state_rc -eq 1 ]]; then
    PROFILE_STATUS="needs-apply"
    PROFILE_REASON="state file is missing"
    return 0
  fi

  if ! all_desired_keys_match "$actual_settings" "$desired_settings" "$desired_keys"; then
    PROFILE_STATUS="needs-apply"
    PROFILE_REASON="managed settings differ from desired values"
    return 0
  fi

  if [[ $(line_count "$stale_keys_present") -gt 0 ]]; then
    PROFILE_STATUS="needs-apply"
    PROFILE_REASON="previously owned settings keys still exist locally"
    return 0
  fi

  if [[ $(line_count "$desired_missing") -gt 0 ]]; then
    PROFILE_STATUS="needs-apply"
    PROFILE_REASON="required extensions are missing"
    return 0
  fi

  if [[ $(line_count "$stale_installed") -gt 0 ]]; then
    PROFILE_STATUS="needs-apply"
    PROFILE_REASON="previously owned extensions still exist locally"
    return 0
  fi

  PROFILE_STATUS="in-sync"
  PROFILE_REASON="managed settings and extensions match desired state"
}

apply_profile() {
  local profile_dir_name="$1"
  local profile_name="$2"
  local desired_settings="$3"
  local desired_extensions="$4"
  local state_file="$5"
  local settings_path="$6"
  local owned_keys_file="$7"
  local owned_extensions_file="$8"
  local desired_keys stale_keys updated_settings desired_missing stale_installed current_extensions stale_owned_extensions extension_id

  ensure_profile_runtime "$profile_dir_name" "$profile_name"

  desired_keys="$(new_tmp_file)"
  stale_keys="$(new_tmp_file)"
  desired_missing="$(new_tmp_file)"
  stale_installed="$(new_tmp_file)"
  updated_settings="$(new_tmp_file)"

  if ! load_state_lists "$state_file" "$profile_dir_name" "$profile_name" "$owned_keys_file" "$owned_extensions_file"; then
    : >"$owned_keys_file"
    : >"$owned_extensions_file"
  fi

  jq -r 'keys_unsorted[]' "$desired_settings" >"$desired_keys"
  file_minus_file "$owned_keys_file" "$desired_keys" "$stale_keys"
  apply_settings_owned_subset "$settings_path" "$desired_settings" "$desired_keys" "$stale_keys" "$updated_settings"
  write_json_atomically "$updated_settings" "$settings_path"

  current_extensions="$(new_tmp_file)"
  stale_owned_extensions="$(new_tmp_file)"
  list_profile_extensions "$profile_dir_name" "$profile_name" "$current_extensions"
  file_minus_file "$desired_extensions" "$current_extensions" "$desired_missing"
  file_minus_file "$owned_extensions_file" "$desired_extensions" "$stale_owned_extensions"
  file_intersection "$stale_owned_extensions" "$current_extensions" "$stale_installed"

  while IFS= read -r extension_id; do
    [[ -n $extension_id ]] || continue
    install_profile_extension "$profile_dir_name" "$profile_name" "$extension_id"
  done <"$desired_missing"

  while IFS= read -r extension_id; do
    [[ -n $extension_id ]] || continue
    uninstall_profile_extension "$profile_dir_name" "$profile_name" "$extension_id"
  done <"$stale_installed"

  write_state_file "$state_file" "$profile_dir_name" "$profile_name" "$desired_keys" "$desired_extensions"
}

list_managed_profiles() {
  local entry

  for entry in "$managed_dir"/*; do
    [[ -d $entry ]] || continue
    entry="$(basename "$entry")"
    [[ $entry == "_default" ]] && continue
    printf '%s\n' "$entry"
  done | sort
}

selected_count=0
checked=0
in_sync=0
needs_apply=0
missing=0
invalid=0
applied=0
errors=0

while IFS= read -r profile_dir_name; do
  [[ -n $profile_dir_name ]] || continue

  if ! profile_selected "$profile_dir_name"; then
    continue
  fi

  selected_count=$((selected_count + 1))
  checked=$((checked + 1))

  profile_name="$(profile_display_name "$profile_dir_name")"
  desired_settings="$(new_tmp_file)"
  desired_extensions="$(new_tmp_file)"
  owned_keys_file="$(new_tmp_file)"
  owned_extensions_file="$(new_tmp_file)"
  state_file="$(profile_state_file "$profile_dir_name")"
  settings_path="$(profile_settings_path "$profile_dir_name")"
  extensions_manifest="$(profile_extensions_manifest_path "$profile_dir_name")"

  build_desired_settings "$profile_dir_name" "$desired_settings"
  build_desired_extensions "$profile_dir_name" "$desired_extensions"
  : >"$owned_keys_file"
  : >"$owned_extensions_file"

  classify_profile \
    "$profile_dir_name" \
    "$profile_name" \
    "$desired_settings" \
    "$desired_extensions" \
    "$state_file" \
    "$settings_path" \
    "$extensions_manifest" \
    "$owned_keys_file" \
    "$owned_extensions_file"

  case "$PROFILE_STATUS" in
  in-sync)
    in_sync=$((in_sync + 1))
    ;;
  needs-apply)
    needs_apply=$((needs_apply + 1))
    ;;
  missing)
    missing=$((missing + 1))
    ;;
  invalid)
    invalid=$((invalid + 1))
    ;;
  *)
    errors=$((errors + 1))
    log "unexpected status for '$profile_dir_name': $PROFILE_STATUS"
    ;;
  esac

  if [[ $details -eq 1 ]]; then
    profile_details "$profile_dir_name" "$profile_name" "$settings_path" "$state_file"
  fi

  if [[ $diff_output -eq 1 && $PROFILE_STATUS != "in-sync" ]]; then
    profile_diff "$profile_dir_name"
  fi

  if [[ $mode == "apply" ]]; then
    case "$PROFILE_STATUS" in
    in-sync) ;;
    missing | needs-apply)
      if apply_profile \
        "$profile_dir_name" \
        "$profile_name" \
        "$desired_settings" \
        "$desired_extensions" \
        "$state_file" \
        "$settings_path" \
        "$owned_keys_file" \
        "$owned_extensions_file"; then
        classify_profile \
          "$profile_dir_name" \
          "$profile_name" \
          "$desired_settings" \
          "$desired_extensions" \
          "$state_file" \
          "$settings_path" \
          "$extensions_manifest" \
          "$owned_keys_file" \
          "$owned_extensions_file"
        if [[ $PROFILE_STATUS == "in-sync" ]]; then
          applied=$((applied + 1))
        else
          errors=$((errors + 1))
          log "apply failed to converge '$profile_dir_name': status=$PROFILE_STATUS"
        fi
      else
        errors=$((errors + 1))
        log "apply failed for '$profile_dir_name'"
      fi
      ;;
    invalid)
      errors=$((errors + 1))
      log "apply refused for '$profile_dir_name': $PROFILE_REASON"
      ;;
    esac
  fi
done < <(list_managed_profiles)

if [[ $selected_count -eq 0 ]]; then
  if [[ -n $profile_filters ]]; then
    die "no profile matched --profile '$profile_filters'"
  fi
  die "no VS Code profiles selected"
fi

if [[ $mode == "apply" && $errors -eq 0 && -z $profile_filters && -d $legacy_instances_dir ]]; then
  rm -rf "$legacy_instances_dir"
fi

log "summary: checked=$checked in_sync=$in_sync needs_apply=$needs_apply missing=$missing invalid=$invalid applied=$applied errors=$errors"

if [[ $mode == "apply" ]]; then
  [[ $errors -eq 0 ]]
  exit $?
fi

if [[ $needs_apply -eq 0 && $missing -eq 0 && $invalid -eq 0 && $errors -eq 0 ]]; then
  exit 0
fi

exit 1
