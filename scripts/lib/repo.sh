#!/usr/bin/env bash

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

flake_ref_for_root() {
  local root="$1"
  printf 'path:%s\n' "$root"
}

list_updateable_root_flake_inputs() {
  local root="$1"

  (
    cd "$root" || exit 1
    nix eval --raw --impure --expr '
      let
        lock = builtins.fromJSON (builtins.readFile ./flake.lock);
        rootInputs = lock.nodes.root.inputs or { };
        isUpdateable = name:
          let
            nodeName = rootInputs.${name};
            node = lock.nodes.${nodeName} or { };
            locked = node.locked or { };
            inputType = locked.type or "";
          in
          inputType != "" && inputType != "path";
        names = builtins.filter isUpdateable (builtins.attrNames rootInputs);
      in
      builtins.concatStringsSep "\n" names
    '
  )
}

resolve_pinned_darwin_rebuild_bin() {
  local flake_ref="$1"
  local build_out=""

  [[ -n $flake_ref ]] || die "flake_ref is required"

  if [[ -n ${DARWIN_REBUILD_BIN:-} ]]; then
    printf '%s\n' "$DARWIN_REBUILD_BIN"
    return 0
  fi

  build_out="$(nix build --no-link --print-out-paths "${flake_ref}#darwin-rebuild")"
  DARWIN_REBUILD_BIN="${build_out}/bin/darwin-rebuild"
  [[ -x $DARWIN_REBUILD_BIN ]] || die "pinned darwin-rebuild not found at $DARWIN_REBUILD_BIN"
  printf '%s\n' "$DARWIN_REBUILD_BIN"
}

resolve_repo_worktree_root_for() {
  local required_path="$1"
  local candidate=""

  if command -v git >/dev/null 2>&1; then
    candidate="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n $candidate && -f $candidate/flake.nix && -d $candidate/$required_path && -d $candidate/scripts ]]; then
      cd "$candidate" && pwd
      return 0
    fi
  fi

  if [[ -f "$(pwd)/flake.nix" && -d "$(pwd)/$required_path" && -d "$(pwd)/scripts" ]]; then
    pwd
    return 0
  fi

  return 1
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

source_dotfiles_script() {
  local script_name="$1"
  local default_script_dir
  local primary
  local fallback

  default_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  primary="${DOTFILES_SCRIPT_DIR:-$default_script_dir}/$script_name"
  local target="$primary"

  fallback="$(pwd)/scripts/$script_name"

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
