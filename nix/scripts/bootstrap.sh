#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOTFILES_SCRIPT_LABEL="bootstrap"

usage() {
  cat <<'USAGE'
Usage: nix run .#bootstrap -- [--host <host>] [--rice <rice>] [--apply] [--yes] [--no-sudo] [--strict]

Environment:
  HOST=...        Host to apply (default: none)
  RICE=...        Rice to apply (default: none)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles-local)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles-secrets)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles-local)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles-secrets)
USAGE
}

host=""
rice=""
apply_after=0
auto_yes=0
no_sudo=0
strict=0

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
    --apply)
      apply_after=1
      shift
      ;;
    --yes)
      apply_after=1
      auto_yes=1
      shift
      ;;
    --no-sudo)
      no_sudo=1
      shift
      ;;
    --strict)
      strict=1
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

if [[ ! -d "$FACTS_DIR" ]]; then
  mkdir -p "$FACTS_DIR"
  log "created $FACTS_DIR"
fi

if [[ ! -d "$SECRETS_DIR" ]]; then
  mkdir -p "$SECRETS_DIR"
  log "created $SECRETS_DIR"
fi

facts_file="$FACTS_DIR/facts.nix"
if [[ ! -f "$facts_file" ]]; then
  username="${USER:-}"
  if [[ -z "$username" ]]; then
    username=$(id -un 2>/dev/null || true)
  fi
  home_dir="${HOME:-}"

  platform=""
  case "$(uname -m 2>/dev/null || true)" in
    arm64) platform="aarch64-darwin" ;;
    x86_64) platform="x86_64-darwin" ;;
  esac

  platform_line=""
  if [[ -n "$platform" ]]; then
    platform_line="    platform = \"${platform}\";"
  fi

  cat >"$facts_file" <<EOF
{
  user = {
    username = "${username}";
    homeDirectory = "${home_dir}";
${platform_line}
  };
}
EOF
  log "generated $facts_file"
fi

secrets_file="$SECRETS_DIR/secrets.nix"
if [[ ! -f "$secrets_file" ]]; then
  cat >"$secrets_file" <<'EOF'
{}
EOF
  log "generated $secrets_file"
fi

age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [[ ! -f "$age_key_file" ]]; then
  if command -v age-keygen >/dev/null 2>&1; then
    mkdir -p "$(dirname "$age_key_file")"
    age-keygen -o "$age_key_file"
    log "generated sops age key at $age_key_file"
  else
    log "age-keygen not found (skipping sops key generation)"
  fi
fi

doctor_args=()
if [[ -n "$host" ]]; then
  doctor_args+=(--host "$host")
fi
if [[ -n "$rice" ]]; then
  doctor_args+=(--rice "$rice")
fi
if [[ "$strict" -eq 1 ]]; then
  doctor_args+=(--strict)
fi

"$SCRIPT_DIR/doctor.sh" "${doctor_args[@]}"

if [[ "$apply_after" -eq 1 ]]; then
  run_apply=0
  if [[ "$auto_yes" -eq 1 ]]; then
    run_apply=1
  elif [[ -t 0 ]]; then
    read -r -p "bootstrap: run apply now? [y/N] " reply
    case "$reply" in
      y|Y|yes|YES) run_apply=1 ;;
    esac
  else
    log "non-interactive shell; skipping apply"
  fi

  if [[ "$run_apply" -eq 1 ]]; then
    apply_args=()
    if [[ -n "$host" ]]; then
      apply_args+=(--host "$host")
    fi
    if [[ -n "$rice" ]]; then
      apply_args+=(--rice "$rice")
    fi
    if [[ "$no_sudo" -eq 1 ]]; then
      apply_args+=(--no-sudo)
    fi
    "$SCRIPT_DIR/apply.sh" "${apply_args[@]}"
  else
    log "skipping apply"
  fi
fi
