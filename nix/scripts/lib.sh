#!/usr/bin/env bash

script_label() {
  basename "${DOTFILES_SCRIPT_LABEL:-$0}"
}

log() {
  printf '%s: %s\n' "$(script_label)" "$*" >&2
}

die() {
  log "$*"
  exit 1
}

set_repo_root() {
  if [[ -n ${DOTFILES_ROOT:-} ]]; then
    if ! ROOT=$(cd "$DOTFILES_ROOT" 2>/dev/null && pwd); then
      die "DOTFILES_ROOT is not a readable directory: $DOTFILES_ROOT"
    fi
  else
    local lib_dir
    lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    ROOT=$(cd "$lib_dir/../.." && pwd)
  fi

  if [[ ! -f "$ROOT/flake.nix" ]]; then
    die "unable to resolve flake root (expected flake.nix under $ROOT)"
  fi
}

resolve_inputs() {
  local default_inputs_dir facts_dir secrets_dir facts_ref secrets_ref
  local facts_path_dir="" secrets_path_dir=""

  default_inputs_dir="$HOME/.config/dotfiles"

  facts_dir="${FACTS_DIR:-}"
  secrets_dir="${SECRETS_DIR:-}"
  facts_ref="${FACTS:-}"
  secrets_ref="${SECRETS:-}"

  if [[ -z $facts_ref ]]; then
    facts_dir="${facts_dir:-$default_inputs_dir}"
    facts_ref="path:${facts_dir}"
  elif [[ -z $facts_dir ]]; then
    facts_dir="$(path_ref_to_dir "$facts_ref" || true)"
  fi

  if [[ -z $secrets_ref ]]; then
    secrets_dir="${secrets_dir:-$default_inputs_dir}"
    secrets_ref="path:${secrets_dir}"
  elif [[ -z $secrets_dir ]]; then
    secrets_dir="$(path_ref_to_dir "$secrets_ref" || true)"
  fi

  if [[ -n $facts_dir ]] && facts_path_dir="$(path_ref_to_dir "$facts_ref" 2>/dev/null || true)" && [[ -n $facts_path_dir && $facts_path_dir != "$facts_dir" ]]; then
    die "FACTS_DIR ($facts_dir) does not match FACTS ($facts_ref)"
  fi

  if [[ -n $secrets_dir ]] && secrets_path_dir="$(path_ref_to_dir "$secrets_ref" 2>/dev/null || true)" && [[ -n $secrets_path_dir && $secrets_path_dir != "$secrets_dir" ]]; then
    die "SECRETS_DIR ($secrets_dir) does not match SECRETS ($secrets_ref)"
  fi

  FACTS_DIR="$facts_dir"
  SECRETS_DIR="$secrets_dir"
  FACTS="$facts_ref"
  SECRETS="$secrets_ref"
}

path_ref_to_dir() {
  local ref="$1"

  case "$ref" in
  path:*)
    printf '%s\n' "${ref#path:}"
    ;;
  *)
    return 1
    ;;
  esac
}

require_input_directories() {
  local command_name="${1:-command}"

  if [[ -z ${FACTS_DIR:-} ]]; then
    die "FACTS_DIR is required when FACTS is not a path:... input ($command_name needs filesystem access)"
  fi

  if [[ -z ${SECRETS_DIR:-} ]]; then
    die "SECRETS_DIR is required when SECRETS is not a path:... input ($command_name needs filesystem access)"
  fi
}

flake_ref_for_root() {
  local root="$1"
  printf 'path:%s\n' "$root"
}

list_darwin_targets() {
  local root="$1"
  local facts="$2"
  local secrets="$3"
  local root_ref

  if ! command -v nix >/dev/null 2>&1; then
    return 1
  fi

  root_ref="$(flake_ref_for_root "$root")"

  nix eval --raw "$root_ref#darwinConfigurations" \
    --apply 'x: builtins.concatStringsSep "\n" (builtins.attrNames x)' \
    --override-input local "$facts" \
    --override-input secrets "$secrets" \
    2>/dev/null
}

resolve_target() {
  local host="$1"
  local rice="$2"
  local root="$3"
  local facts="$4"
  local secrets="$5"

  if [[ -z $host ]]; then
    log "host is required"
    return 1
  fi

  local targets
  if ! targets=$(list_darwin_targets "$root" "$facts" "$secrets"); then
    log "unable to evaluate darwinConfigurations (check local/secrets inputs and STUB)"
    return 1
  fi

  if [[ -z $targets ]]; then
    log "no darwinConfigurations found (check local/secrets inputs and STUB)"
    return 1
  fi

  local found_host=0
  local found_combo=0
  local target
  while IFS= read -r target; do
    [[ -z $target ]] && continue
    [[ $target == "$host" ]] && found_host=1
    if [[ -n $rice && $target == "${host}-${rice}" ]]; then
      found_combo=1
    fi
  done <<<"$targets"

  if [[ -z $rice ]]; then
    if [[ $found_host -eq 1 ]]; then
      printf '%s\n' "$host"
      return 0
    fi
  else
    if [[ $found_combo -eq 1 ]]; then
      printf '%s\n' "${host}-${rice}"
      return 0
    fi
  fi

  log "target not found for host '$host'${rice:+ and rice '$rice'}"
  log "available darwinConfigurations:"
  while IFS= read -r target; do
    [[ -z $target ]] && continue
    printf '  - %s\n' "$target" >&2
  done <<<"$targets"
  return 1
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

resolve_repo_worktree_root_for() {
  local required_path="$1"
  local candidate=""

  if command -v git >/dev/null 2>&1; then
    candidate="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n $candidate && -f $candidate/flake.nix && -d $candidate/$required_path && -d $candidate/nix/scripts ]]; then
      cd "$candidate" && pwd
      return 0
    fi
  fi

  if [[ -f "$(pwd)/flake.nix" && -d "$(pwd)/$required_path" && -d "$(pwd)/nix/scripts" ]]; then
    pwd
    return 0
  fi

  return 1
}

parse_target_args() {
  local value_options="${PARSE_TARGET_VALUE_OPTIONS:-}"

  PARSED_HOST=""
  PARSED_RICE=""
  PARSED_ARGS=()
  PARSED_PASSTHROUGH=()
  PARSED_HAS_PASSTHROUGH=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --host)
      [[ $# -lt 2 ]] && die "missing value for --host"
      PARSED_HOST="$2"
      shift 2
      ;;
    --rice)
      [[ $# -lt 2 ]] && die "missing value for --rice"
      PARSED_RICE="$2"
      shift 2
      ;;
    --)
      shift
      PARSED_HAS_PASSTHROUGH=1
      PARSED_PASSTHROUGH=("$@")
      break
      ;;
    *)
      if [[ $1 == --* ]]; then
        if [[ -n $value_options && " $value_options " == *" $1 "* ]]; then
          [[ $# -lt 2 ]] && die "missing value for $1"
          PARSED_ARGS+=("$1" "$2")
          shift 2
          continue
        fi
        PARSED_ARGS+=("$1")
      elif [[ -z $PARSED_HOST ]]; then
        PARSED_HOST="$1"
      else
        PARSED_ARGS+=("$1")
      fi
      shift
      ;;
    esac
  done
}

require_writable_checkout() {
  local root="$1"
  local start_dir="${2:-$PWD}"
  local resolved_root="$root"

  if [[ $resolved_root == /nix/store/* ]]; then
    if [[ -f "$start_dir/flake.nix" && -f "$start_dir/flake.lock" && -w "$start_dir/flake.nix" && -w "$start_dir/flake.lock" ]]; then
      log "resolved store root for CLI; using writable checkout at $start_dir for update"
      resolved_root="$start_dir"
    fi
  fi

  if [[ ! -f "$resolved_root/flake.lock" ]]; then
    die "flake.lock not found under $resolved_root (update requires a writable checkout)"
  fi

  if [[ ! -w "$resolved_root/flake.nix" || ! -w "$resolved_root/flake.lock" ]]; then
    die "update requires a writable flake checkout (current root: $resolved_root)"
  fi

  printf '%s\n' "$resolved_root"
}

ensure_inputs_dirs() {
  local facts_dir="$1"
  local secrets_dir="$2"

  if [[ ! -d $facts_dir ]]; then
    mkdir -p "$facts_dir"
    log "created $facts_dir"
  fi
  chmod 700 "$facts_dir"

  if [[ ! -d $secrets_dir ]]; then
    mkdir -p "$secrets_dir"
    log "created $secrets_dir"
  fi
  chmod 700 "$secrets_dir"
}

source_dotfiles_script() {
  local script_name="$1"
  local primary="${DOTFILES_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/$script_name"
  local fallback
  local target="$primary"

  fallback="$(pwd)/nix/scripts/$script_name"

  if [[ ! -f $target ]]; then
    if [[ -f $fallback ]]; then
      target="$fallback"
    else
      die "$script_name not found (tried $primary and $fallback)"
    fi
  fi

  # shellcheck disable=SC1090
  source "$target"
}
