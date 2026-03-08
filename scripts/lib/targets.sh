#!/usr/bin/env bash

log_input_resolution_hint() {
  local label="$1"
  local ref="$2"
  local expected_file="$3"
  local input_dir="" stub_path=""

  log "$label input: $ref"

  input_dir="$(path_ref_to_dir "$ref" 2>/dev/null || true)"
  if [[ -z $input_dir ]]; then
    return 0
  fi

  if [[ ! -f "$input_dir/$expected_file" ]]; then
    log "$label file missing: $input_dir/$expected_file"
  fi

  stub_path="$input_dir/STUB"
  if [[ -f $stub_path ]]; then
    log "$label STUB present: $stub_path (flake outputs are gated while it exists)"
  fi
}

log_darwin_configuration_hints() {
  local facts="$1"
  local secrets="$2"

  log_input_resolution_hint "facts" "$facts" "facts.nix"
  log_input_resolution_hint "secrets" "$secrets" "secrets.nix"
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
    --no-update-lock-file \
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
    log_darwin_configuration_hints "$facts" "$secrets"
    return 1
  fi

  if [[ -z $targets ]]; then
    log "no darwinConfigurations found (check local/secrets inputs and STUB)"
    log_darwin_configuration_hints "$facts" "$secrets"
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

require_host_argument() {
  local host="${1:-}"
  local command_name="${2:-command}"

  if [[ -n $host ]]; then
    return 0
  fi

  die "host is required for $command_name (pass --host <host>, a positional host, or HOST=...)"
}

parse_target_args() {
  local value_options="${PARSE_TARGET_VALUE_OPTIONS:-}"

  PARSED_HOST=""
  # shellcheck disable=SC2034
  PARSED_RICE=""
  PARSED_ARGS=()
  # shellcheck disable=SC2034
  PARSED_PASSTHROUGH=()
  # shellcheck disable=SC2034
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
      # shellcheck disable=SC2034
      PARSED_RICE="$2"
      shift 2
      ;;
    --)
      shift
      # shellcheck disable=SC2034
      PARSED_HAS_PASSTHROUGH=1
      # shellcheck disable=SC2034
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
