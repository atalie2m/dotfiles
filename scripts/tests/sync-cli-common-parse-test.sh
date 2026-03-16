#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$ROOT/scripts/sync.sh"
APPLY_SCRIPT="$ROOT/scripts/apply.sh"
UPDATE_SCRIPT="$ROOT/scripts/update.sh"
LIST_TOOLS_SCRIPT="$ROOT/scripts/list-tools.sh"
DOCTOR_SCRIPT="$ROOT/scripts/doctor.sh"
BOOTSTRAP_SCRIPT="$ROOT/scripts/bootstrap.sh"
DOTFILES_SCRIPT="$ROOT/scripts/dotfiles.sh"
SOURCE_MANAGED_DIR="$ROOT/surfaces/shell/desired"
REAL_DOTFILES_BIN="${DOTFILES_BIN:-$(command -v dotfiles 2>/dev/null || true)}"

for required in \
  "$SYNC_SCRIPT" \
  "$APPLY_SCRIPT" \
  "$UPDATE_SCRIPT" \
  "$LIST_TOOLS_SCRIPT" \
  "$DOCTOR_SCRIPT" \
  "$BOOTSTRAP_SCRIPT" \
  "$DOTFILES_SCRIPT"; do
  if [[ ! -f $required ]]; then
    echo "test: required script not found: $required" >&2
    exit 1
  fi
done

if [[ ! -d $SOURCE_MANAGED_DIR ]]; then
  echo "test: managed dir not found: $SOURCE_MANAGED_DIR" >&2
  exit 1
fi

if [[ -z $REAL_DOTFILES_BIN || ! -x $REAL_DOTFILES_BIN ]]; then
  echo "test: DOTFILES_BIN or dotfiles binary is required" >&2
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

run_real() {
  DOTFILES_BIN="$REAL_DOTFILES_BIN" "$@"
}

run_shell_sync() {
  HOME="$shell_home" run_real bash "$SYNC_SCRIPT" shell "$@" --managed-dir "$shell_managed"
}

assert_wrapper_subcommand() {
  local script="$1"
  local expected="$2"
  shift 2

  local fake_bin="$tmp_root/fake-dotfiles"
  local log_file
  log_file="$tmp_root/$(basename "$script").log"
  cat >"$fake_bin" <<'EOF_FAKE_DOTFILES'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${FAKE_DOTFILES_LOG_FILE:?}"
EOF_FAKE_DOTFILES
  chmod +x "$fake_bin"

  FAKE_DOTFILES_LOG_FILE="$log_file" \
    DOTFILES_BIN="$fake_bin" \
    bash "$script" "$@" >/dev/null

  if ! grep -Fqx "$expected" "$log_file"; then
    echo "FAIL: wrapper delegation changed for $script" >&2
    cat "$log_file" >&2 || true
    exit 1
  fi
}

assert_missing_host() {
  local script="$1"
  local command_name="$2"
  local stdout_file="$3"
  local stderr_file="$4"

  shift 4

  if run_real bash "$script" "$@" >"$stdout_file" 2>"$stderr_file"; then
    echo "FAIL: $command_name unexpectedly accepted missing host" >&2
    exit 1
  fi

  if ! grep -Fq "host is required for $command_name (pass --host <host>, a positional host, or HOST=...)" "$stderr_file"; then
    echo "FAIL: $command_name missing-host message changed" >&2
    cat "$stderr_file" >&2 || true
    exit 1
  fi
}

printf 'test: running sync cli common parse test\n'
printf 'test: temp root = %s\n' "$tmp_root"

assert_wrapper_subcommand "$APPLY_SCRIPT" "apply --host pro_mac --action build" --host pro_mac --action build
assert_wrapper_subcommand "$DOTFILES_SCRIPT" "sync shell --check" sync shell --check

if ! run_shell_sync --apply --item bash-rc >/dev/null; then
  echo "FAIL: shell apply failed" >&2
  exit 1
fi
if ! run_shell_sync --check --item bash-rc >/dev/null; then
  echo "FAIL: shell check failed after apply" >&2
  exit 1
fi
if ! HOME="$shell_home" "$REAL_DOTFILES_BIN" sync shell --check --item bash-rc --managed-dir "$shell_managed" >/dev/null; then
  echo "FAIL: direct CLI shell check failed after apply" >&2
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

if run_real bash "$SYNC_SCRIPT" terminal --check >/dev/null 2>"$tmp_root/terminal.err"; then
  echo "FAIL: sync unexpectedly accepted removed terminal surface" >&2
  exit 1
fi
if ! grep -Fq "invalid value 'terminal' for '<SURFACE>'" "$tmp_root/terminal.err"; then
  echo "FAIL: removed terminal surface did not report expected error" >&2
  cat "$tmp_root/terminal.err" >&2 || true
  exit 1
fi

assert_missing_host "$APPLY_SCRIPT" "apply" "$tmp_root/apply.out" "$tmp_root/apply.err"
assert_missing_host "$UPDATE_SCRIPT" "update" "$tmp_root/update.out" "$tmp_root/update.err"
assert_missing_host "$LIST_TOOLS_SCRIPT" "list-tools" "$tmp_root/list-tools.out" "$tmp_root/list-tools.err"
assert_missing_host "$BOOTSTRAP_SCRIPT" "bootstrap" "$tmp_root/bootstrap-missing-host.out" "$tmp_root/bootstrap-missing-host.err" --apply

if (
  unset FACTS FACTS_DIR SECRETS SECRETS_DIR
  export FACTS="github:example/facts"
  run_real bash "$DOCTOR_SCRIPT"
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
  export SECRETS="github:example/secrets"
  run_real bash "$BOOTSTRAP_SCRIPT" --host ultra_mac
) >"$tmp_root/bootstrap.out" 2>"$tmp_root/bootstrap.err"; then
  echo "FAIL: bootstrap unexpectedly accepted SECRETS without SECRETS_DIR" >&2
  exit 1
fi
if ! grep -Fq "SECRETS_DIR is required when SECRETS is not a path:... input (bootstrap needs filesystem access)" "$tmp_root/bootstrap.err"; then
  echo "FAIL: bootstrap missing non-path SECRETS guidance" >&2
  cat "$tmp_root/bootstrap.err" >&2 || true
  exit 1
fi

empty_nix_bin="$tmp_root/empty-nix-bin"
mkdir -p "$empty_nix_bin"
cat >"$empty_nix_bin/nix" <<'EOF_EMPTY_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 6 && $1 == "eval" && $2 == "--json" && $3 == path:*#darwinConfigurations && $4 == "--impure" && $5 == "--apply" ]]; then
  if [[ $6 == *"targets-manifest.nix"* ]]; then
    printf '{"hosts":{}}'
    exit 0
  fi
fi

if [[ $# -ge 3 && $1 == "eval" && $2 == "--raw" && $3 == path:*#darwinConfigurations ]]; then
  exit 0
fi

echo "fake nix: unexpected invocation: $*" >&2
exit 1
EOF_EMPTY_NIX
chmod +x "$empty_nix_bin/nix"

empty_home="$tmp_root/empty-home"
mkdir -p "$empty_home/.config/dotfiles"
cat >"$empty_home/.config/dotfiles/facts.nix" <<'EOF_EMPTY_FACTS'
{
  user.username = "tester";
}
EOF_EMPTY_FACTS
cat >"$empty_home/.config/dotfiles/secrets.nix" <<'EOF_EMPTY_SECRETS'
{
  files = { };
}
EOF_EMPTY_SECRETS

if (
  HOME="$empty_home" \
    PATH="$empty_nix_bin:$PATH" \
    run_real bash "$APPLY_SCRIPT" --host ultra_mac
) >"$tmp_root/apply-empty.out" 2>"$tmp_root/apply-empty.err"; then
  echo "FAIL: apply unexpectedly accepted an empty darwinConfigurations set" >&2
  exit 1
fi
if ! grep -Fq "no darwinConfigurations found (check local/secrets inputs)" "$tmp_root/apply-empty.err"; then
  echo "FAIL: apply missing empty-target guidance" >&2
  cat "$tmp_root/apply-empty.err" >&2 || true
  exit 1
fi
if ! grep -Fq "facts input: path:$empty_home/.config/dotfiles" "$tmp_root/apply-empty.err"; then
  echo "FAIL: apply missing facts input path for empty target set" >&2
  cat "$tmp_root/apply-empty.err" >&2 || true
  exit 1
fi
if grep -Fq "STUB" "$tmp_root/apply-empty.err"; then
  echo "FAIL: apply still mentions STUB for empty target set" >&2
  cat "$tmp_root/apply-empty.err" >&2 || true
  exit 1
fi

failing_nix_bin="$tmp_root/failing-nix-bin"
mkdir -p "$failing_nix_bin"
cat >"$failing_nix_bin/nix" <<'EOF_FAILING_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 6 && $1 == "eval" && $2 == "--json" && $3 == path:*#darwinConfigurations && $4 == "--impure" && $5 == "--apply" ]]; then
  if [[ $6 == *"targets-manifest.nix"* ]]; then
    exit 1
  fi
fi

if [[ $# -ge 3 && $1 == "eval" && $2 == "--raw" && $3 == path:*#darwinConfigurations ]]; then
  exit 1
fi

echo "fake nix: unexpected invocation: $*" >&2
exit 1
EOF_FAILING_NIX
chmod +x "$failing_nix_bin/nix"

failing_home="$tmp_root/failing-home"
mkdir -p "$failing_home/.config/dotfiles"
cat >"$failing_home/.config/dotfiles/facts.nix" <<'EOF_FAILING_FACTS'
{
  user.username = "tester";
}
EOF_FAILING_FACTS
cat >"$failing_home/.config/dotfiles/secrets.nix" <<'EOF_FAILING_SECRETS'
{
  files = { };
}
EOF_FAILING_SECRETS

if (
  HOME="$failing_home" \
    PATH="$failing_nix_bin:$PATH" \
    run_real bash "$APPLY_SCRIPT" --host ultra_mac
) >"$tmp_root/apply-failing-eval.out" 2>"$tmp_root/apply-failing-eval.err"; then
  echo "FAIL: apply unexpectedly accepted a failing darwinConfigurations eval" >&2
  exit 1
fi
if ! grep -Fq "unable to evaluate darwinConfigurations (check local/secrets inputs)" "$tmp_root/apply-failing-eval.err"; then
  echo "FAIL: apply missing darwinConfigurations eval guidance" >&2
  cat "$tmp_root/apply-failing-eval.err" >&2 || true
  exit 1
fi
if ! grep -Fq "facts input: path:$failing_home/.config/dotfiles" "$tmp_root/apply-failing-eval.err"; then
  echo "FAIL: apply missing facts input path for eval failures" >&2
  cat "$tmp_root/apply-failing-eval.err" >&2 || true
  exit 1
fi
if ! grep -Fq "secrets input: path:$failing_home/.config/dotfiles" "$tmp_root/apply-failing-eval.err"; then
  echo "FAIL: apply missing secrets input path for eval failures" >&2
  cat "$tmp_root/apply-failing-eval.err" >&2 || true
  exit 1
fi
if grep -Fq "STUB" "$tmp_root/apply-failing-eval.err"; then
  echo "FAIL: apply still mentions STUB for eval failures" >&2
  cat "$tmp_root/apply-failing-eval.err" >&2 || true
  exit 1
fi

fake_bin="$tmp_root/fake-bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/nix" <<'EOF_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 4 && $1 == "eval" && $2 == "--raw" && $3 == "--impure" && $4 == "--expr" ]]; then
  if [[ "$*" == *"facts-schema.nix"* ]]; then
    if [[ "$*" == *"/doctor-home/.config/dotfiles/facts.nix"* ]]; then
      cat <<'EOF_SCHEMA'
facts.migration|fail|facts.user.stateVersion.nixos has been removed; delete it from facts.nix
EOF_SCHEMA
      exit 0
    fi

    cat <<'EOF_SCHEMA'
facts.schema.root|ok|facts is an attrset
facts.schema.user|ok|facts.user is an attrset
facts.username|ok|tester
facts.stateVersion|ok|facts.user.stateVersion set
facts.stateVersion.home|ok|25.11
facts.stateVersion.darwin|ok|6
EOF_SCHEMA
    exit 0
  fi

  if [[ "$*" == *"facts-template.nix"* ]]; then
    cat <<'EOF_FACTS'
{
  user = {
    username = "tester";

    # Optional for Git identity:
    # fullName = "Your Name";
    # email = "you@example.com";

    # Optional overrides:
    # homeDirectory = "/Users/tester";
    # stateVersion = {
    #   home = "25.11";
    #   darwin = 6;
    # };
  };

  # Optional machine metadata for tools.system.hostnames:
  # machines = {
  #   ultra_mac = {
  #     computerName = "Your Mac";
  #     localHostName = "your-mac";
  #     hostName = "your-mac";
  #     domain = "local";
  #   };
  # };
}
EOF_FACTS
    exit 0
  fi
fi

if [[ $# -ge 6 && $1 == "eval" && $2 == "--json" && $3 == path:*#darwinConfigurations && $4 == "--impure" && $5 == "--apply" ]]; then
  if [[ $6 == *"targets-manifest.nix"* ]]; then
    if [[ $3 == *"empty-home"* ]]; then
      printf '{"hosts":{}}'
      exit 0
    fi

    cat <<'EOF_MANIFEST'
{"hosts":{"pro_mac":{"defaultRice":"pro","buildTarget":"pro_mac","supportedRices":["base","darwin","dev","partial","pro","ultra"],"machineKey":"pro_mac","system":"aarch64-darwin","targetsByRice":{"base":"pro_mac-base","darwin":"pro_mac-darwin","dev":"pro_mac-dev","partial":"pro_mac-partial","pro":"pro_mac","ultra":"pro_mac-ultra"}},"ultra_mac":{"defaultRice":"ultra","buildTarget":"ultra_mac","supportedRices":["base","darwin","dev","partial","pro","ultra"],"machineKey":"ultra_mac","system":"aarch64-darwin","targetsByRice":{"base":"ultra_mac-base","darwin":"ultra_mac-darwin","dev":"ultra_mac-dev","partial":"ultra_mac-partial","pro":"ultra_mac-pro","ultra":"ultra_mac"}},"minimal_mac":{"defaultRice":"base","buildTarget":"minimal_mac","supportedRices":["base","darwin","dev","partial","pro","ultra"],"machineKey":"minimal_mac","system":"aarch64-darwin","targetsByRice":{"base":"minimal_mac","darwin":"minimal_mac-darwin","dev":"minimal_mac-dev","partial":"minimal_mac-partial","pro":"minimal_mac-pro","ultra":"minimal_mac-ultra"}}}}
EOF_MANIFEST
    exit 0
  fi
fi

if [[ $# -ge 3 && $1 == "eval" && $2 == "--raw" && $3 == path:*#darwinConfigurations ]]; then
  printf 'pro_mac\nultra_mac\nminimal_mac\n'
  exit 0
fi

if [[ $# -ge 2 && $1 == "flake" && $2 == "check" ]]; then
  exit 0
fi

echo "fake nix: unexpected invocation: $*" >&2
exit 1
EOF_NIX
chmod +x "$fake_bin/nix"

bootstrap_home="$tmp_root/bootstrap-home"
if ! (
  HOME="$bootstrap_home" \
    PATH="$fake_bin:$PATH" \
    run_real bash "$BOOTSTRAP_SCRIPT"
) >"$tmp_root/bootstrap-hostless.out" 2>"$tmp_root/bootstrap-hostless.err"; then
  echo "FAIL: bootstrap unexpectedly failed without host" >&2
  cat "$tmp_root/bootstrap-hostless.out" >&2 || true
  cat "$tmp_root/bootstrap-hostless.err" >&2 || true
  exit 1
fi

bootstrap_facts_file="$bootstrap_home/.config/dotfiles/facts.nix"
bootstrap_secrets_file="$bootstrap_home/.config/dotfiles/secrets.nix"
if [[ ! -f $bootstrap_facts_file || ! -f $bootstrap_secrets_file ]]; then
  echo "FAIL: bootstrap did not create facts/secrets files without host" >&2
  exit 1
fi
if ! grep -Fq 'username = "tester";' "$bootstrap_facts_file"; then
  echo "FAIL: bootstrap did not render the canonical facts template" >&2
  cat "$bootstrap_facts_file" >&2 || true
  exit 1
fi
if ! grep -Fq '# homeDirectory = "/Users/tester";' "$bootstrap_facts_file"; then
  echo "FAIL: bootstrap homeDirectory example changed unexpectedly" >&2
  cat "$bootstrap_facts_file" >&2 || true
  exit 1
fi
if ! grep -Fq '#     domain = "local";' "$bootstrap_facts_file"; then
  echo "FAIL: bootstrap machine schema example is missing domain" >&2
  cat "$bootstrap_facts_file" >&2 || true
  exit 1
fi
if grep -Fq 'platform =' "$bootstrap_facts_file"; then
  echo "FAIL: bootstrap still emitted deprecated platform facts" >&2
  cat "$bootstrap_facts_file" >&2 || true
  exit 1
fi
if grep -Fq 'STUB' "$tmp_root/bootstrap-hostless.err"; then
  echo "FAIL: bootstrap still mentioned STUB" >&2
  cat "$tmp_root/bootstrap-hostless.err" >&2 || true
  exit 1
fi

doctor_home="$tmp_root/doctor-home"
mkdir -p "$doctor_home/.config/dotfiles"
cat >"$doctor_home/.config/dotfiles/facts.nix" <<'EOF_DOCTOR_FACTS'
{
  user = {
    username = "tester";
    stateVersion = {
      home = "25.11";
      darwin = 6;
      nixos = "25.11";
    };
  };
}
EOF_DOCTOR_FACTS
cat >"$doctor_home/.config/dotfiles/secrets.nix" <<'EOF_DOCTOR_SECRETS'
{
  files = { };
}
EOF_DOCTOR_SECRETS

if (
  HOME="$doctor_home" \
    PATH="$fake_bin:$PATH" \
    run_real bash "$DOCTOR_SCRIPT" --strict
) >"$tmp_root/doctor-strict.out" 2>"$tmp_root/doctor-strict.err"; then
  echo "FAIL: doctor --strict unexpectedly accepted removed facts.user.stateVersion.nixos" >&2
  cat "$tmp_root/doctor-strict.out" >&2 || true
  cat "$tmp_root/doctor-strict.err" >&2 || true
  exit 1
fi
if ! grep -Fq "warn  shell.sync: strict sync check skipped (pass --host to resolve target)" "$tmp_root/doctor-strict.out"; then
  echo "FAIL: doctor --strict did not warn about skipped host-aware sync checks" >&2
  cat "$tmp_root/doctor-strict.out" >&2 || true
  exit 1
fi
if ! grep -Fq "fail  facts.migration: facts.user.stateVersion.nixos has been removed; delete it from facts.nix" "$tmp_root/doctor-strict.out"; then
  echo "FAIL: doctor --strict missing removed stateVersion migration error" >&2
  cat "$tmp_root/doctor-strict.out" >&2 || true
  exit 1
fi

echo "PASS: sync cli common parse"
