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
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -z ${ROOT:-} ]]; then
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

default_rice_for_host() {
  local root="$1"
  local host="$2"
  local host_file="$root/nix/denix/hosts/$host/default.nix"
  if [[ ! -f $host_file ]]; then
    return 0
  fi
  sed -nE 's/^[[:space:]]*rice[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$host_file" | head -n 1
}

list_darwin_targets() {
  local root="$1"
  local facts="$2"
  local secrets="$3"

  if ! command -v nix >/dev/null 2>&1; then
    return 1
  fi

  nix eval --raw "$root#darwinConfigurations" \
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
    local default_rice
    default_rice=$(default_rice_for_host "$root" "$host")
    if [[ -n $default_rice && $default_rice == "$rice" && $found_host -eq 1 ]]; then
      printf '%s\n' "$host"
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
