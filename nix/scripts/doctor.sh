#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOTFILES_SCRIPT_LABEL="doctor"

usage() {
  cat <<'USAGE'
Usage: nix run .#doctor -- [--host <host>] [--rice <rice>] [--strict] [--json]

Environment:
  HOST=...        Host to inspect (default: none)
  RICE=...        Rice to inspect (default: none)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles-local)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles-secrets)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles-local)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles-secrets)
USAGE
}

host=""
rice=""
strict=0
json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --host)
      [[ $# -lt 2 ]] && die "missing value for --host"
      host="$2"
      shift 2
      ;;
    --rice)
      [[ $# -lt 2 ]] && die "missing value for --rice"
      rice="$2"
      shift 2
      ;;
    --strict)
      strict=1
      shift
      ;;
    --json)
      json=1
      shift
      ;;
    --)
      die "unexpected -- (no passthrough supported)"
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      die "unexpected argument: $1"
      ;;
  esac
done

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"

set_repo_root
cd "$ROOT"
resolve_inputs

CHECK_NAMES=()
CHECK_STATUS=()
CHECK_MESSAGE=()
FAILURES=0
WARNINGS=0

record_check() {
  local name="$1"
  local status="$2"
  local message="$3"

  CHECK_NAMES+=("$name")
  CHECK_STATUS+=("$status")
  CHECK_MESSAGE+=("$message")

  case "$status" in
    fail) FAILURES=$((FAILURES + 1)) ;;
    warn) WARNINGS=$((WARNINGS + 1)) ;;
  esac

  if [[ "$json" -eq 0 ]]; then
    printf '%-5s %s: %s\n' "$status" "$name" "$message"
  fi
}

facts_file="$FACTS_DIR/facts.nix"
if [[ -f "$facts_file" ]]; then
  record_check "facts.exists" "ok" "$facts_file"
  if command -v nix >/dev/null 2>&1; then
    if username=$(nix eval --raw --file "$facts_file" --apply 'x: x.user.username or ""' 2>/dev/null); then
      if [[ -n "$username" ]]; then
        record_check "facts.username" "ok" "$username"
      else
        record_check "facts.username" "fail" "facts.user.username is empty"
      fi
    else
      record_check "facts.username" "fail" "unable to evaluate facts.user.username"
    fi

    if home_dir=$(nix eval --raw --file "$facts_file" --apply 'x: x.user.homeDirectory or ""' 2>/dev/null); then
      if [[ -n "$home_dir" ]]; then
        record_check "facts.homeDirectory" "ok" "$home_dir"
      else
        record_check "facts.homeDirectory" "fail" "facts.user.homeDirectory is empty"
      fi
    else
      record_check "facts.homeDirectory" "fail" "unable to evaluate facts.user.homeDirectory"
    fi
  else
    record_check "facts.eval" "fail" "nix not found (cannot evaluate facts)"
  fi
else
  record_check "facts.exists" "fail" "$facts_file missing"
fi

if [[ -f "$FACTS_DIR/STUB" ]]; then
  record_check "facts.stub" "fail" "STUB present in $FACTS_DIR (flake outputs are gated)"
else
  record_check "facts.stub" "ok" "no STUB in $FACTS_DIR"
fi

secrets_file="$SECRETS_DIR/secrets.nix"
if [[ -f "$secrets_file" ]]; then
  record_check "secrets.exists" "ok" "$secrets_file"
else
  record_check "secrets.exists" "fail" "$secrets_file missing"
fi

age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [[ -f "$age_key_file" ]]; then
  record_check "sops.ageKey" "ok" "$age_key_file"
else
  record_check "sops.ageKey" "warn" "$age_key_file missing"
fi

if command -v xcode-select >/dev/null 2>&1; then
  if xcode_path=$(xcode-select -p 2>/dev/null); then
    record_check "darwin.xcodeSelect" "ok" "$xcode_path"
  else
    record_check "darwin.xcodeSelect" "fail" "Command Line Tools not configured"
  fi
else
  record_check "darwin.xcodeSelect" "fail" "xcode-select not found"
fi

machine_arch=$(uname -m 2>/dev/null || true)
if [[ "$machine_arch" == "arm64" ]]; then
  if command -v arch >/dev/null 2>&1 && arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    record_check "darwin.rosetta" "ok" "Rosetta available"
  else
    record_check "darwin.rosetta" "warn" "Rosetta not available"
  fi
else
  record_check "darwin.rosetta" "ok" "Not required on $machine_arch"
fi

if command -v nix >/dev/null 2>&1; then
  if targets=$(list_darwin_targets "$ROOT" "$FACTS" "$SECRETS"); then
    if [[ -z "$targets" ]]; then
      record_check "flake.targets" "fail" "no darwinConfigurations found"
    elif [[ -n "$host" ]]; then
      if [[ "$json" -eq 1 ]]; then
        target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS" 2>/dev/null || true)
      else
        target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS" || true)
      fi
      if [[ -n "$target" ]]; then
        if nix eval --raw "$ROOT#darwinConfigurations.${target}.system.drvPath" \
          --override-input local "$FACTS" \
          --override-input secrets "$SECRETS" \
          >/dev/null 2>&1; then
          record_check "flake.target" "ok" "$target"
        else
          record_check "flake.target" "fail" "unable to evaluate darwinConfigurations.${target}.system"
        fi
      else
        record_check "flake.target" "fail" "target resolution failed"
      fi
    else
      target_count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
      record_check "flake.targets" "ok" "darwinConfigurations available ($target_count targets)"
    fi
  else
    record_check "flake.targets" "fail" "unable to evaluate darwinConfigurations"
  fi
else
  record_check "flake.targets" "fail" "nix not found (cannot evaluate flake)"
fi

if [[ "$strict" -eq 1 ]]; then
  if nix flake check \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS" \
    >/dev/null 2>&1; then
    record_check "flake.check" "ok" "nix flake check passed"
  else
    record_check "flake.check" "fail" "nix flake check failed"
  fi
fi

if [[ "$json" -eq 1 ]]; then
  ok="false"
  if [[ "$FAILURES" -eq 0 ]]; then
    ok="true"
  fi
  printf '{'
  printf '"ok":%s,' "$ok"
  printf '"failures":%s,' "$FAILURES"
  printf '"warnings":%s,' "$WARNINGS"
  printf '"checks":['
  for i in "${!CHECK_NAMES[@]}"; do
    name=$(json_escape "${CHECK_NAMES[$i]}")
    status=$(json_escape "${CHECK_STATUS[$i]}")
    message=$(json_escape "${CHECK_MESSAGE[$i]}")
    printf '{"name":"%s","status":"%s","message":"%s"}' "$name" "$status" "$message"
    if [[ "$i" -lt $((${#CHECK_NAMES[@]} - 1)) ]]; then
      printf ','
    fi
  done
  printf ']}\n'
fi

if [[ "$FAILURES" -eq 0 ]]; then
  exit 0
fi
exit 1
