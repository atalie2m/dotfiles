#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOAD_LIB="$ROOT/nix/scripts/load-lib.sh"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
SOURCE_MANAGED_DIR="$ROOT/surfaces/shell/desired"
DOCTOR_SCRIPT="$ROOT/nix/scripts/doctor.sh"
BOOTSTRAP_SCRIPT="$ROOT/nix/scripts/bootstrap.sh"

if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $LOAD_LIB ]]; then
  echo "test: load-lib script not found: $LOAD_LIB" >&2
  exit 1
fi

if [[ ! -f $DOCTOR_SCRIPT ]]; then
  echo "test: doctor script not found: $DOCTOR_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $BOOTSTRAP_SCRIPT ]]; then
  echo "test: bootstrap script not found: $BOOTSTRAP_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-cli-common.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

shell_home="$tmp_root/shell-home"
shell_managed="$tmp_root/shell-managed"

mkdir -p "$shell_home"
cp -R "$SOURCE_MANAGED_DIR" "$shell_managed"
chmod -R u+w "$shell_managed"

run_shell_sync() {
  HOME="$shell_home" bash "$SYNC_SCRIPT" shell "$@" --managed-dir "$shell_managed"
}

run_resolve_inputs() {
  local home_dir="$1"
  shift

  (
    export HOME="$home_dir"
    mkdir -p "$HOME"
    unset FACTS FACTS_DIR SECRETS SECRETS_DIR

    while [[ $# -gt 0 ]]; do
      export "${1%%=*}=${1#*=}"
      shift
    done

    DOTFILES_SCRIPT_LABEL="sync-cli-common-parse-test"
    # shellcheck source=load-lib.sh
    source "$LOAD_LIB"
    resolve_inputs
    printf 'FACTS_DIR=%s\n' "${FACTS_DIR:-}"
    printf 'SECRETS_DIR=%s\n' "${SECRETS_DIR:-}"
    printf 'FACTS=%s\n' "${FACTS:-}"
    printf 'SECRETS=%s\n' "${SECRETS:-}"
  )
}

assert_line() {
  local file="$1"
  local expected="$2"

  if ! grep -Fqx "$expected" "$file"; then
    echo "FAIL: missing expected line: $expected" >&2
    cat "$file" >&2 || true
    exit 1
  fi
}

printf 'test: running sync cli common parse test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: shell apply failed" >&2
  exit 1
fi
if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: shell check failed after apply" >&2
  exit 1
fi

missing_item="missing-parse-item"
if run_shell_sync --check --item "$missing_item" >/dev/null 2>"$tmp_root/shell.err"; then
  echo "FAIL: shell check unexpectedly passed for missing --item" >&2
  exit 1
fi
if ! grep -Fq "no item matched --item '$missing_item'" "$tmp_root/shell.err"; then
  echo "FAIL: shell missing-item message did not use expected wording" >&2
  exit 1
fi

for removed in --migrate --adopt --forget --state-dir --force --in-place --output-dir; do
  case "$removed" in
  --state-dir | --output-dir)
    if run_shell_sync "$removed" "$tmp_root/unused" >/dev/null 2>"$tmp_root/${removed#--}.err"; then
      echo "FAIL: shell unexpectedly accepted removed option $removed" >&2
      exit 1
    fi
    ;;
  *)
    if run_shell_sync "$removed" >/dev/null 2>"$tmp_root/${removed#--}.err"; then
      echo "FAIL: shell unexpectedly accepted removed option $removed" >&2
      exit 1
    fi
    ;;
  esac
  if ! grep -Fq -- "$removed is no longer supported for sync shell" "$tmp_root/${removed#--}.err"; then
    echo "FAIL: shell removed-option message missing for $removed" >&2
    cat "$tmp_root/${removed#--}.err" >&2 || true
    exit 1
  fi
done

if bash "$SYNC_SCRIPT" terminal --check >/dev/null 2>"$tmp_root/terminal.err"; then
  echo "FAIL: sync unexpectedly accepted removed terminal surface" >&2
  exit 1
fi
if ! grep -Fq "unknown sync surface: terminal (expected: shell)" "$tmp_root/terminal.err"; then
  echo "FAIL: removed terminal surface did not report expected error" >&2
  cat "$tmp_root/terminal.err" >&2 || true
  exit 1
fi

default_home="$tmp_root/default-home"
default_out="$tmp_root/default.out"
run_resolve_inputs "$default_home" >"$default_out"
assert_line "$default_out" "FACTS_DIR=$default_home/.config/dotfiles"
assert_line "$default_out" "SECRETS_DIR=$default_home/.config/dotfiles"
assert_line "$default_out" "FACTS=path:$default_home/.config/dotfiles"
assert_line "$default_out" "SECRETS=path:$default_home/.config/dotfiles"

explicit_home="$tmp_root/explicit-home"
explicit_facts_dir="$tmp_root/custom-facts"
explicit_secrets_dir="$tmp_root/custom-secrets"
explicit_out="$tmp_root/explicit.out"
run_resolve_inputs "$explicit_home" \
  "FACTS_DIR=$explicit_facts_dir" \
  "SECRETS_DIR=$explicit_secrets_dir" \
  >"$explicit_out"
assert_line "$explicit_out" "FACTS_DIR=$explicit_facts_dir"
assert_line "$explicit_out" "SECRETS_DIR=$explicit_secrets_dir"
assert_line "$explicit_out" "FACTS=path:$explicit_facts_dir"
assert_line "$explicit_out" "SECRETS=path:$explicit_secrets_dir"

path_home="$tmp_root/path-home"
path_facts_dir="$tmp_root/path-facts"
path_secrets_dir="$tmp_root/path-secrets"
path_out="$tmp_root/path.out"
run_resolve_inputs "$path_home" \
  "FACTS=path:$path_facts_dir" \
  "SECRETS=path:$path_secrets_dir" \
  >"$path_out"
assert_line "$path_out" "FACTS_DIR=$path_facts_dir"
assert_line "$path_out" "SECRETS_DIR=$path_secrets_dir"
assert_line "$path_out" "FACTS=path:$path_facts_dir"
assert_line "$path_out" "SECRETS=path:$path_secrets_dir"

if (
  unset FACTS FACTS_DIR SECRETS SECRETS_DIR
  FACTS="github:example/facts" bash "$DOCTOR_SCRIPT"
) >"$tmp_root/doctor.out" 2>"$tmp_root/doctor.err"; then
  echo "FAIL: doctor unexpectedly accepted FACTS without FACTS_DIR" >&2
  exit 1
fi
if ! grep -Fq "FACTS_DIR is required when FACTS is not a path:... input (doctor needs filesystem access)" "$tmp_root/doctor.err"; then
  echo "FAIL: doctor missing non-path FACTS guidance" >&2
  cat "$tmp_root/doctor.err" >&2 || true
  exit 1
fi

if (
  unset FACTS FACTS_DIR SECRETS SECRETS_DIR
  SECRETS="github:example/secrets" bash "$BOOTSTRAP_SCRIPT"
) >"$tmp_root/bootstrap.out" 2>"$tmp_root/bootstrap.err"; then
  echo "FAIL: bootstrap unexpectedly accepted SECRETS without SECRETS_DIR" >&2
  exit 1
fi
if ! grep -Fq "SECRETS_DIR is required when SECRETS is not a path:... input (bootstrap needs filesystem access)" "$tmp_root/bootstrap.err"; then
  echo "FAIL: bootstrap missing non-path SECRETS guidance" >&2
  cat "$tmp_root/bootstrap.err" >&2 || true
  exit 1
fi

echo "PASS: sync cli common parse"
