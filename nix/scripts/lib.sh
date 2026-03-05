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
  FACTS_DIR="${FACTS_DIR:-$HOME/.config/dotfiles}"
  SECRETS_DIR="${SECRETS_DIR:-$HOME/.config/dotfiles}"
  FACTS="${FACTS:-path:${FACTS_DIR}}"
  SECRETS="${SECRETS:-path:${SECRETS_DIR}}"
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
