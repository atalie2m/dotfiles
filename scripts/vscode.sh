#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="vscode"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- vscode launch --profile <name> [--managed-dir <path>] [--print-command] [--] [code args...]

Subcommands:
  launch    Launch VS Code with the selected native profile and any launch-only disabled extensions
USAGE
}

launch_usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- vscode launch --profile <name> [--managed-dir <path>] [--print-command] [--] [code args...]

Options:
  --profile <name>     Managed profile dir name to launch (for example: native, web, python)
  --managed-dir <path> Profile definitions directory (default: <repo>/apps/vscode)
  --print-command      Print the resolved code command instead of executing it
  --help               Show this help

Behavior:
  - Reads launch-only disabled extensions from:
      apps/vscode/_default/launch-disabled-extensions.txt
      apps/vscode/<profile>/launch-disabled-extensions.txt
  - Launches VS Code with repeated --disable-extension flags.
  - `native` launches the built-in Default profile without passing --profile.
USAGE
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

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
launch) ;;
help | -h | --help)
  usage
  exit 0
  ;;
*)
  die "unknown vscode subcommand: $subcommand"
  ;;
esac

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

managed_dir=""
profile_dir_name=""
print_command=0
launch_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --profile)
    [[ $# -lt 2 ]] && die "missing value for --profile"
    profile_dir_name="$2"
    shift 2
    ;;
  --managed-dir)
    [[ $# -lt 2 ]] && die "missing value for --managed-dir"
    managed_dir="$2"
    shift 2
    ;;
  --print-command)
    print_command=1
    shift
    ;;
  --help | -h)
    launch_usage
    exit 0
    ;;
  --)
    shift
    launch_args=("$@")
    break
    ;;
  *)
    launch_args+=("$1")
    shift
    ;;
  esac
done

if [[ -z $managed_dir ]]; then
  set_repo_root
  managed_dir="$ROOT/apps/vscode"
fi

[[ -d $managed_dir ]] || die "managed dir not found: $managed_dir"
[[ -d $managed_dir/_default ]] || die "managed default profile dir not found: $managed_dir/_default"
[[ -n $profile_dir_name ]] || die "--profile is required"
[[ -d $managed_dir/$profile_dir_name ]] || die "managed profile dir not found: $managed_dir/$profile_dir_name"

code_bin="${VSCODE_CODE_BIN:-$(command -v code 2>/dev/null || true)}"
[[ -n $code_bin ]] || die "VS Code CLI not found in PATH (expected 'code')"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/vscode-launch.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

default_disabled="$tmp_dir/default-disabled.txt"
profile_disabled="$tmp_dir/profile-disabled.txt"
merged_disabled="$tmp_dir/merged-disabled.txt"

filter_extensions_file "$managed_dir/_default/launch-disabled-extensions.txt" "$default_disabled"
filter_extensions_file "$managed_dir/$profile_dir_name/launch-disabled-extensions.txt" "$profile_disabled"
awk '!seen[$0]++' "$default_disabled" "$profile_disabled" >"$merged_disabled"

profile_name="$(profile_display_name "$profile_dir_name")"
vscode_data_home="${VSCODE_DATA_HOME:-$HOME/Library/Application Support/Code}"

cmd=("$code_bin" "--user-data-dir" "$vscode_data_home")

if [[ $profile_dir_name != "native" ]]; then
  cmd+=("--profile" "$profile_name")
fi

while IFS= read -r extension_id; do
  [[ -n $extension_id ]] || continue
  cmd+=("--disable-extension" "$extension_id")
done <"$merged_disabled"

if [[ ${#launch_args[@]} -gt 0 ]]; then
  cmd+=("${launch_args[@]}")
fi

if [[ $print_command -eq 1 ]]; then
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

exec "${cmd[@]}"
