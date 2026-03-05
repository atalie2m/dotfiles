#!/usr/bin/env bash
set -euo pipefail
umask 077

DOTFILES_SCRIPT_LABEL="bootstrap"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#bootstrap -- [--host <host>] [--rice <rice>] [--apply] [--yes] [--no-sudo] [--strict]

Environment:
  HOST=...        Host to apply (default: none)
  RICE=...        Rice to apply (default: none)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles)
USAGE
}

host=""
rice=""
apply_after=0
auto_yes=0
no_sudo=0
strict=0

if [[ $# -gt 0 ]]; then
  case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  esac
fi

parse_target_args "$@"
if [[ $PARSED_HAS_PASSTHROUGH -eq 1 ]]; then
  die "unexpected -- (no passthrough supported)"
fi

host="$PARSED_HOST"
rice="$PARSED_RICE"

for arg in "${PARSED_ARGS[@]}"; do
  case "$arg" in
  --apply)
    apply_after=1
    ;;
  --yes)
    apply_after=1
    auto_yes=1
    ;;
  --no-sudo)
    no_sudo=1
    ;;
  --strict)
    strict=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    die "unknown option: $arg"
    ;;
  *)
    die "unexpected argument: $arg"
    ;;
  esac
done

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"

set_repo_root
cd "$ROOT"
resolve_inputs
ensure_inputs_dirs "$FACTS_DIR" "$SECRETS_DIR"

facts_file="$FACTS_DIR/facts.nix"
if [[ ! -f $facts_file ]]; then
  username="${USER:-}"
  if [[ -z $username ]]; then
    username=$(id -un 2>/dev/null || true)
  fi
  if [[ -z $username ]]; then
    username="yourname"
  fi

  cat >"$facts_file" <<EOF
{
  user = {
    username = "${username}";

    # Optional for Git identity:
    # fullName = "Your Name";
    # email = "you@example.com";

    # Optional overrides:
    # homeDirectory = "/Users/${username}";
    # platform = "x86_64-darwin"; # default is aarch64-darwin
  };

  # Optional machine metadata for tools.system.hostnames:
  # machines = {
  #   a2m_mac = {
  #     computerName = "Your Mac";
  #     localHostName = "your-mac";
  #     hostName = "your-mac";
  #   };
  # };
}
EOF
  log "generated $facts_file"
fi
chmod 600 "$facts_file"

secrets_file="$SECRETS_DIR/secrets.nix"
if [[ ! -f $secrets_file ]]; then
  cat >"$secrets_file" <<'EOF'
{}
EOF
  log "generated $secrets_file"
fi
chmod 600 "$secrets_file"

age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [[ ! -f $age_key_file ]]; then
  if command -v age-keygen >/dev/null 2>&1; then
    mkdir -p "$(dirname "$age_key_file")"
    chmod 700 "$(dirname "$age_key_file")"
    age-keygen -o "$age_key_file"
    chmod 600 "$age_key_file"
    log "generated sops age key at $age_key_file"
  else
    log "age-keygen not found (skipping sops key generation)"
  fi
fi

if [[ -f $age_key_file ]]; then
  chmod 600 "$age_key_file"
fi

doctor_args=()
if [[ -n $host ]]; then
  doctor_args+=(--host "$host")
fi
if [[ -n $rice ]]; then
  doctor_args+=(--rice "$rice")
fi
if [[ $strict -eq 1 ]]; then
  doctor_args+=(--strict)
fi

"$DOTFILES_SCRIPT_DIR/doctor.sh" "${doctor_args[@]}"

if [[ $apply_after -eq 1 ]]; then
  run_apply=0
  if [[ $auto_yes -eq 1 ]]; then
    run_apply=1
  elif [[ -t 0 ]]; then
    read -r -p "bootstrap: run apply now? [y/N] " reply
    case "$reply" in
    y | Y | yes | YES) run_apply=1 ;;
    esac
  else
    log "non-interactive shell; skipping apply"
  fi

  if [[ $run_apply -eq 1 ]]; then
    apply_args=()
    if [[ -n $host ]]; then
      apply_args+=(--host "$host")
    fi
    if [[ -n $rice ]]; then
      apply_args+=(--rice "$rice")
    fi
    if [[ $no_sudo -eq 1 ]]; then
      apply_args+=(--no-sudo)
    fi
    "$DOTFILES_SCRIPT_DIR/apply.sh" "${apply_args[@]}"
  else
    log "skipping apply"
  fi
fi
