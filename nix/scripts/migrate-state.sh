#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="migrate-state"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  nix run .#dotfiles -- migrate-state [--dry-run] [--force]

Description:
  Migrate dotfiles sync state directories to the normalized layout:
    shell:    $XDG_STATE_HOME/dotfiles/shell/blocks
          ->  $XDG_STATE_HOME/dotfiles/sync/shell/blocks
    terminal: $XDG_STATE_HOME/dotfiles/terminal-app/profiles
          ->  $XDG_STATE_HOME/dotfiles/sync/terminal-app/profiles
    terminal (legacy): $XDG_STATE_HOME/dotfiles/terminal/profiles
                    -> $XDG_STATE_HOME/dotfiles/sync/terminal-app/profiles

Options:
  --dry-run  Show planned moves/merges without changing files
  --force    Allow merge into an existing destination directory
  -h, --help Show this help text
USAGE
}

dry_run=0
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    dry_run=1
    ;;
  --force)
    force=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
  shift
done

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"

old_shell_dir="$state_home/dotfiles/shell/blocks"
old_terminal_dir="$state_home/dotfiles/terminal-app/profiles"
old_terminal_legacy_dir="$state_home/dotfiles/terminal/profiles"

new_shell_dir="$state_home/dotfiles/sync/shell/blocks"
new_terminal_dir="$state_home/dotfiles/sync/terminal-app/profiles"

planned_changes=0
applied_changes=0

has_entries() {
  local dir="$1"
  find "$dir" -mindepth 1 -print -quit | grep -q .
}

plan() {
  planned_changes=$((planned_changes + 1))
}

applied() {
  applied_changes=$((applied_changes + 1))
}

move_or_merge_dir() {
  local source_dir="$1"
  local destination_dir="$2"
  local label="$3"

  if [[ ! -e $source_dir ]]; then
    log "skip $label (source missing): $source_dir"
    return 0
  fi

  if [[ ! -d $source_dir ]]; then
    die "source is not a directory for $label: $source_dir"
  fi

  if [[ ! -e $destination_dir ]]; then
    plan
    if [[ $dry_run -eq 1 ]]; then
      log "dry-run: move $label"
      log "  from: $source_dir"
      log "    to: $destination_dir"
      return 0
    fi

    mkdir -p "$(dirname "$destination_dir")"
    mv "$source_dir" "$destination_dir"
    log "moved $label"
    log "  from: $source_dir"
    log "    to: $destination_dir"
    applied
    return 0
  fi

  if [[ ! -d $destination_dir ]]; then
    die "destination exists but is not a directory for $label: $destination_dir"
  fi

  if ! has_entries "$source_dir"; then
    plan
    if [[ $dry_run -eq 1 ]]; then
      log "dry-run: remove empty source directory for $label: $source_dir"
      return 0
    fi

    rmdir "$source_dir" >/dev/null 2>&1 || rm -rf "$source_dir"
    log "removed empty source directory for $label: $source_dir"
    applied
    return 0
  fi

  if [[ $force -ne 1 ]]; then
    die "destination already exists for $label: $destination_dir (rerun with --force to merge and remove source $source_dir)"
  fi

  plan
  if [[ $dry_run -eq 1 ]]; then
    log "dry-run: merge $label into existing destination"
    log "  from: $source_dir"
    log "    to: $destination_dir"
    return 0
  fi

  mkdir -p "$destination_dir"
  cp -R "$source_dir"/. "$destination_dir"/
  rm -rf "$source_dir"
  log "merged $label into existing destination"
  log "  from: $source_dir"
  log "    to: $destination_dir"
  applied
}

log "state root: $state_home"
move_or_merge_dir "$old_shell_dir" "$new_shell_dir" "shell sync state"
move_or_merge_dir "$old_terminal_dir" "$new_terminal_dir" "terminal sync state"
move_or_merge_dir "$old_terminal_legacy_dir" "$new_terminal_dir" "terminal legacy sync state"

if [[ $planned_changes -eq 0 ]]; then
  log "no migration actions needed"
  exit 0
fi

if [[ $dry_run -eq 1 ]]; then
  log "dry-run complete: planned_changes=$planned_changes"
  exit 0
fi

log "migration complete: applied_changes=$applied_changes"
