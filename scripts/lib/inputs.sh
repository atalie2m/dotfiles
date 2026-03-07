#!/usr/bin/env bash

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

require_input_directories() {
  local command_name="${1:-command}"

  if [[ -z ${FACTS_DIR:-} ]]; then
    die "FACTS_DIR is required when FACTS is not a path:... input ($command_name needs filesystem access)"
  fi

  if [[ -z ${SECRETS_DIR:-} ]]; then
    die "SECRETS_DIR is required when SECRETS is not a path:... input ($command_name needs filesystem access)"
  fi
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
