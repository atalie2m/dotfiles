#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  nix/scripts/vscode-instances.sh bootstrap --name <name> --base-dir <path> --code-bin <path> --settings-json <path> --extensions-txt <path> --baseline-id <id>
  nix/scripts/vscode-instances.sh launch --name <name> --base-dir <path> --code-bin <path> --settings-json <path> --extensions-txt <path> --disabled-extensions-txt <path> --baseline-id <id> [-- <code args...>]
  nix/scripts/vscode-instances.sh reset --name <name> --base-dir <path> --code-bin <path> --settings-json <path> --extensions-txt <path> --baseline-id <id>
USAGE
}

log() {
  printf 'vscode-instances: %s\n' "$*" >&2
}

require_non_empty() {
  local value="$1"
  local flag_name="$2"
  [[ -n $value ]] || {
    log "missing required flag: $flag_name"
    exit 1
  }
}

load_common_args() {
  instance_name=""
  base_dir=""
  code_bin=""
  settings_json=""
  extensions_txt=""
  disabled_extensions_txt=""
  baseline_id=""
  launch_passthrough=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --name)
      [[ $# -lt 2 ]] && {
        log "missing value for --name"
        exit 1
      }
      instance_name="$2"
      shift 2
      ;;
    --base-dir)
      [[ $# -lt 2 ]] && {
        log "missing value for --base-dir"
        exit 1
      }
      base_dir="$2"
      shift 2
      ;;
    --code-bin)
      [[ $# -lt 2 ]] && {
        log "missing value for --code-bin"
        exit 1
      }
      code_bin="$2"
      shift 2
      ;;
    --settings-json)
      [[ $# -lt 2 ]] && {
        log "missing value for --settings-json"
        exit 1
      }
      settings_json="$2"
      shift 2
      ;;
    --extensions-txt)
      [[ $# -lt 2 ]] && {
        log "missing value for --extensions-txt"
        exit 1
      }
      extensions_txt="$2"
      shift 2
      ;;
    --disabled-extensions-txt)
      [[ $# -lt 2 ]] && {
        log "missing value for --disabled-extensions-txt"
        exit 1
      }
      disabled_extensions_txt="$2"
      shift 2
      ;;
    --baseline-id)
      [[ $# -lt 2 ]] && {
        log "missing value for --baseline-id"
        exit 1
      }
      baseline_id="$2"
      shift 2
      ;;
    --)
      shift
      launch_passthrough=("$@")
      break
      ;;
    *)
      log "unknown option: $1"
      exit 1
      ;;
    esac
  done

  require_non_empty "$instance_name" "--name"
  require_non_empty "$base_dir" "--base-dir"
  require_non_empty "$code_bin" "--code-bin"
  require_non_empty "$settings_json" "--settings-json"
  require_non_empty "$extensions_txt" "--extensions-txt"
  require_non_empty "$baseline_id" "--baseline-id"
}

instance_data_dir() {
  printf '%s\n' "${base_dir}/${instance_name}/user-data"
}

instance_extensions_dir() {
  printf '%s\n' "${base_dir}/${instance_name}/extensions"
}

instance_marker_path() {
  printf '%s\n' "$(instance_data_dir)/.dotfiles-baseline"
}

bootstrap_instance() {
  command -v jq >/dev/null 2>&1 || {
    log "jq is required for bootstrap"
    exit 1
  }

  local data exts user_dir marker wanted installed force tmpdir tmp ext
  data="$(instance_data_dir)"
  exts="$(instance_extensions_dir)"
  user_dir="$data/User"
  marker="$(instance_marker_path)"
  wanted="$baseline_id"

  mkdir -p "$user_dir" "$exts"

  if [[ -f "$user_dir/settings.json" ]]; then
    cp "$user_dir/settings.json" "$user_dir/settings.json.bak.$(date +%s)"
    tmpdir="${TMPDIR:-/tmp}"
    tmp="$(mktemp "$tmpdir/vscode-settings.XXXXXX")"
    jq -s '
      def force($base; $path):
        ($base | getpath($path)) as $v
        | if $v == null then . else setpath($path; $v) end;

      .[0] as $base | .[1] as $user
      | ($base * $user)
      | force($base; ["window.title"])
      | force($base; ["window.titleSeparator"])
      | force($base; ["workbench.colorCustomizations","titleBar.activeBackground"])
      | force($base; ["workbench.colorCustomizations","titleBar.inactiveBackground"])
      | force($base; ["workbench.colorCustomizations","statusBar.background"])
      | force($base; ["workbench.colorCustomizations","statusBar.noFolderBackground"])
    ' "$settings_json" "$user_dir/settings.json" >"$tmp"
    mv "$tmp" "$user_dir/settings.json"
  else
    cp "$settings_json" "$user_dir/settings.json"
  fi

  installed="$("$code_bin" --user-data-dir "$data" --extensions-dir "$exts" --list-extensions 2>/dev/null || true)"
  force="${VSCODE_FORCE_EXTENSIONS:-0}"

  while IFS= read -r ext; do
    [[ -z $ext ]] && continue
    case "$ext" in
    \#*) continue ;;
    esac

    if [[ $force == "1" ]]; then
      "$code_bin" --user-data-dir "$data" --extensions-dir "$exts" --install-extension "$ext" --force || true
      continue
    fi

    if printf '%s\n' "$installed" | grep -Fxq "$ext"; then
      continue
    fi

    "$code_bin" --user-data-dir "$data" --extensions-dir "$exts" --install-extension "$ext" || true
  done <"$extensions_txt"

  printf '%s' "$wanted" >"$marker"
}

launch_instance() {
  local data exts marker wanted ext
  local disable_args=()

  data="$(instance_data_dir)"
  exts="$(instance_extensions_dir)"
  marker="$(instance_marker_path)"
  wanted="$baseline_id"

  if [[ ${VSCODE_SKIP_BOOTSTRAP:-0} != "1" ]]; then
    if [[ ! -f $marker || "$(cat "$marker" 2>/dev/null || true)" != "$wanted" ]]; then
      bootstrap_instance
    fi
  fi

  [[ -n $disabled_extensions_txt ]] || {
    log "missing required flag for launch: --disabled-extensions-txt"
    exit 1
  }

  while IFS= read -r ext; do
    [[ -z $ext ]] && continue
    case "$ext" in
    \#*) continue ;;
    esac
    disable_args+=(--disable-extension "$ext")
  done <"$disabled_extensions_txt"

  exec "$code_bin" \
    --user-data-dir "$data" \
    --extensions-dir "$exts" \
    --new-window \
    "${disable_args[@]}" \
    "${launch_passthrough[@]}"
}

reset_instance() {
  local base ts backup
  base="${base_dir}/${instance_name}"

  if [[ -d $base ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${base}.backup-${ts}"
    mv "$base" "$backup"
    printf 'Backed up %s to %s\n' "$base" "$backup"
  fi

  bootstrap_instance
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
bootstrap)
  load_common_args "$@"
  bootstrap_instance
  ;;
launch)
  load_common_args "$@"
  launch_instance
  ;;
reset)
  load_common_args "$@"
  reset_instance
  ;;
-h | --help | help)
  usage
  ;;
*)
  log "unknown subcommand: $subcommand"
  usage >&2
  exit 1
  ;;
esac
