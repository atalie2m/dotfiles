#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOAD_LIB="$ROOT/scripts/lib/load-lib.sh"
SYNC_SCRIPT="$ROOT/scripts/sync.sh"
SOURCE_MANAGED_DIR="$ROOT/surfaces/shell/desired"
APPLY_SCRIPT="$ROOT/scripts/apply.sh"
UPDATE_SCRIPT="$ROOT/scripts/update.sh"
LIST_TOOLS_SCRIPT="$ROOT/scripts/list-tools.sh"
DOCTOR_SCRIPT="$ROOT/scripts/doctor.sh"
BOOTSTRAP_SCRIPT="$ROOT/scripts/bootstrap.sh"

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

if [[ ! -f $APPLY_SCRIPT ]]; then
  echo "test: apply script not found: $APPLY_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $UPDATE_SCRIPT ]]; then
  echo "test: update script not found: $UPDATE_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $LIST_TOOLS_SCRIPT ]]; then
  echo "test: list-tools script not found: $LIST_TOOLS_SCRIPT" >&2
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

    export DOTFILES_SCRIPT_LABEL="sync-cli-common-parse-test"
    # shellcheck source=lib/load-lib.sh
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

assert_missing_host() {
  local script="$1"
  local command_name="$2"
  local stdout_file="$3"
  local stderr_file="$4"

  shift 4

  if bash "$script" "$@" >"$stdout_file" 2>"$stderr_file"; then
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
if ! grep -Fq "unknown sync surface: terminal (expected: shell or vscode)" "$tmp_root/terminal.err"; then
  echo "FAIL: removed terminal surface did not report expected error" >&2
  cat "$tmp_root/terminal.err" >&2 || true
  exit 1
fi

assert_missing_host "$APPLY_SCRIPT" "apply" "$tmp_root/apply.out" "$tmp_root/apply.err"
assert_missing_host "$UPDATE_SCRIPT" "update" "$tmp_root/update.out" "$tmp_root/update.err"
assert_missing_host "$LIST_TOOLS_SCRIPT" "list-tools" "$tmp_root/list-tools.out" "$tmp_root/list-tools.err"
assert_missing_host "$BOOTSTRAP_SCRIPT" "bootstrap" "$tmp_root/bootstrap-missing-host.out" "$tmp_root/bootstrap-missing-host.err" --apply

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
  SECRETS="github:example/secrets" bash "$BOOTSTRAP_SCRIPT" --host ultra_mac
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

if [[ $# -ge 3 && $1 == "eval" && $2 == "--raw" && $3 == path:*#darwinConfigurations ]]; then
  exit 0
fi

echo "fake nix: unexpected invocation: $*" >&2
exit 1
EOF_EMPTY_NIX
chmod +x "$empty_nix_bin/nix"

stub_home="$tmp_root/stub-home"
mkdir -p "$stub_home/.config/dotfiles"
: >"$stub_home/.config/dotfiles/STUB"

if (
  HOME="$stub_home" \
    PATH="$empty_nix_bin:$PATH" \
    bash "$APPLY_SCRIPT" --host ultra_mac
) >"$tmp_root/apply-stub.out" 2>"$tmp_root/apply-stub.err"; then
  echo "FAIL: apply unexpectedly accepted a stubbed facts input" >&2
  exit 1
fi

if ! grep -Fq "no darwinConfigurations found (check local/secrets inputs and STUB)" "$tmp_root/apply-stub.err"; then
  echo "FAIL: apply missing empty-target guidance" >&2
  cat "$tmp_root/apply-stub.err" >&2 || true
  exit 1
fi
if ! grep -Fq "facts input: path:$stub_home/.config/dotfiles" "$tmp_root/apply-stub.err"; then
  echo "FAIL: apply missing facts input path for stubbed inputs" >&2
  cat "$tmp_root/apply-stub.err" >&2 || true
  exit 1
fi
if ! grep -Fq "facts STUB present: $stub_home/.config/dotfiles/STUB (flake outputs are gated while it exists)" "$tmp_root/apply-stub.err"; then
  echo "FAIL: apply missing stub-path guidance" >&2
  cat "$tmp_root/apply-stub.err" >&2 || true
  exit 1
fi

failing_nix_bin="$tmp_root/failing-nix-bin"
mkdir -p "$failing_nix_bin"
cat >"$failing_nix_bin/nix" <<'EOF_FAILING_NIX'
#!/usr/bin/env bash
set -euo pipefail

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
{}
EOF_FAILING_SECRETS

if (
  HOME="$failing_home" \
    PATH="$failing_nix_bin:$PATH" \
    bash "$APPLY_SCRIPT" --host ultra_mac
) >"$tmp_root/apply-failing-eval.out" 2>"$tmp_root/apply-failing-eval.err"; then
  echo "FAIL: apply unexpectedly accepted a failing darwinConfigurations eval" >&2
  exit 1
fi

if ! grep -Fq "unable to evaluate darwinConfigurations (check local/secrets inputs and STUB)" "$tmp_root/apply-failing-eval.err"; then
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

fake_bin="$tmp_root/fake-bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/nix" <<'EOF_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 4 && $1 == "eval" && $2 == "--raw" && $3 == "--impure" && $4 == "--expr" ]]; then
  if [[ "$*" == *"facts-schema.nix"* ]]; then
    cat <<'EOF_SCHEMA'
facts.schema.root|ok|facts is an attrset
facts.schema.user|ok|facts.user is an attrset
facts.username|ok|tester
facts.stateVersion|ok|facts.user.stateVersion set
facts.stateVersion.home|ok|25.11
facts.stateVersion.darwin|ok|6
facts.stateVersion.nixos|ok|25.11
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
  #   };
  # };
}
EOF_FACTS
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

cat >"$fake_bin/darwin-rebuild" <<'EOF_REBUILD'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${FAKE_REBUILD_LOG_FILE:?}"
exit 0
EOF_REBUILD
chmod +x "$fake_bin/darwin-rebuild"

cat >"$fake_bin/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -euo pipefail

preserve_env=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preserve-env=*)
      preserve_env="$1"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "fake sudo: unexpected option: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

printf '%s\n' "$preserve_env" >"${FAKE_SUDO_LOG_FILE:?}"
printf '%s\n' "$*" >"${FAKE_SUDO_COMMAND_FILE:?}"
exec "$@"
EOF_SUDO
chmod +x "$fake_bin/sudo"

real_uname="$(command -v uname)"
cat >"$fake_bin/uname" <<EOF_UNAME
#!/usr/bin/env bash
set -euo pipefail

case "\${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'x86_64\n' ;;
  *) exec "$real_uname" "\$@" ;;
esac
EOF_UNAME
chmod +x "$fake_bin/uname"

cat >"$fake_bin/xcode-select" <<'EOF_XCODE'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "-p" ]]; then
  printf '/Applications/Xcode.app/Contents/Developer\n'
  exit 0
fi

exit 1
EOF_XCODE
chmod +x "$fake_bin/xcode-select"

bootstrap_home="$tmp_root/bootstrap-home"
if ! (
  HOME="$bootstrap_home" \
    PATH="$fake_bin:$PATH" \
    bash "$BOOTSTRAP_SCRIPT"
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
if grep -Fq 'platform =' "$bootstrap_facts_file"; then
  echo "FAIL: bootstrap still emitted deprecated platform facts" >&2
  cat "$bootstrap_facts_file" >&2 || true
  exit 1
fi

doctor_home="$tmp_root/doctor-home"
mkdir -p "$doctor_home/.config/dotfiles"
cat >"$doctor_home/.config/dotfiles/facts.nix" <<'EOF_FACTS'
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
EOF_FACTS
cat >"$doctor_home/.config/dotfiles/secrets.nix" <<'EOF_SECRETS'
{}
EOF_SECRETS

if ! (
  HOME="$doctor_home" \
    PATH="$fake_bin:$PATH" \
    bash "$DOCTOR_SCRIPT" --strict
) >"$tmp_root/doctor-strict.out" 2>"$tmp_root/doctor-strict.err"; then
  echo "FAIL: doctor --strict unexpectedly failed without host" >&2
  cat "$tmp_root/doctor-strict.out" >&2 || true
  cat "$tmp_root/doctor-strict.err" >&2 || true
  exit 1
fi

if ! grep -Fq "warn  shell.sync: strict sync check skipped (pass --host to resolve target)" "$tmp_root/doctor-strict.out"; then
  echo "FAIL: doctor --strict did not warn about skipped host-aware sync checks" >&2
  cat "$tmp_root/doctor-strict.out" >&2 || true
  exit 1
fi

apply_home="$tmp_root/apply-home"
mkdir -p "$apply_home/.config/dotfiles"

if ! (
  HOME="$apply_home" \
    PATH="$fake_bin:$PATH" \
    DARWIN_REBUILD_BIN="$fake_bin/darwin-rebuild" \
    FAKE_SUDO_LOG_FILE="$tmp_root/apply-sudo.log" \
    FAKE_SUDO_COMMAND_FILE="$tmp_root/apply-sudo-command.log" \
    FAKE_REBUILD_LOG_FILE="$tmp_root/apply-rebuild.log" \
    bash "$APPLY_SCRIPT" --host ultra_mac --action build -- --show-trace
) >"$tmp_root/apply-run.out" 2>"$tmp_root/apply-run.err"; then
  echo "FAIL: apply unexpectedly failed under fake sudo/darwin-rebuild" >&2
  cat "$tmp_root/apply-run.out" >&2 || true
  cat "$tmp_root/apply-run.err" >&2 || true
  exit 1
fi

expected_preserve_env="--preserve-env=PATH,DARWIN_REBUILD_BIN"
if [[ -n ${DOTFILES_ROOT:-} ]]; then
  expected_preserve_env="${expected_preserve_env},DOTFILES_ROOT"
fi
if [[ $(cat "$tmp_root/apply-sudo.log") != "$expected_preserve_env" ]]; then
  echo "FAIL: apply did not use the expected sudo preserve-env set" >&2
  printf 'expected: %s\nactual:   %s\n' "$expected_preserve_env" "$(cat "$tmp_root/apply-sudo.log")" >&2
  exit 1
fi

expected_facts_ref="path:$apply_home/.config/dotfiles"
if ! grep -Fq -- "build --flake path:$ROOT#ultra_mac --no-update-lock-file --override-input local $expected_facts_ref --override-input secrets $expected_facts_ref --show-trace" "$tmp_root/apply-rebuild.log"; then
  echo "FAIL: apply did not pass the expected darwin-rebuild arguments" >&2
  cat "$tmp_root/apply-rebuild.log" >&2 || true
  exit 1
fi

tool_path_bin="$tmp_root/tool-path-bin"
tool_path_log="$tmp_root/tool-path.log"
tool_path_home="$tmp_root/tool-path-home"
tool_path_managed="$tmp_root/tool-path-managed"
mkdir -p "$tool_path_bin" "$tool_path_home"
cp -R "$SOURCE_MANAGED_DIR" "$tool_path_managed"
chmod -R u+w "$tool_path_managed"

real_awk="$(command -v awk)"
real_diff="$(command -v diff)"
real_grep="$(command -v grep)"

cat >"$tool_path_bin/awk" <<EOF_AWK
#!/usr/bin/env bash
set -euo pipefail
printf 'awk\n' >>"$tool_path_log"
exec "$real_awk" "\$@"
EOF_AWK
chmod +x "$tool_path_bin/awk"

cat >"$tool_path_bin/diff" <<EOF_DIFF
#!/usr/bin/env bash
set -euo pipefail
printf 'diff\n' >>"$tool_path_log"
exec "$real_diff" "\$@"
EOF_DIFF
chmod +x "$tool_path_bin/diff"

cat >"$tool_path_bin/grep" <<EOF_GREP
#!/usr/bin/env bash
set -euo pipefail
printf 'grep\n' >>"$tool_path_log"
exec "$real_grep" "\$@"
EOF_GREP
chmod +x "$tool_path_bin/grep"

run_with_fake_tools() {
  HOME="$tool_path_home" PATH="$tool_path_bin:$PATH" "$@"
}

if ! run_with_fake_tools bash "$SYNC_SCRIPT" shell --apply --item bash-rc --managed-dir "$tool_path_managed" >/dev/null; then
  echo "FAIL: shell apply failed under fake PATH tools" >&2
  exit 1
fi

cat >"$tool_path_home/.bashrc" <<'EOF_BASHRC'
# >>> dotfiles-managed:bashrc >>>
# drift
# <<< dotfiles-managed:bashrc <<<
EOF_BASHRC

if run_with_fake_tools bash "$SYNC_SCRIPT" shell --check --diff --item bash-rc --managed-dir "$tool_path_managed" >"$tmp_root/tool-path-shell.out" 2>"$tmp_root/tool-path-shell.err"; then
  echo "FAIL: shell diff unexpectedly succeeded for drifted content" >&2
  exit 1
fi

printf '%s\n' '# user zshrc' >"$tool_path_home/.zshrc"
if ! run_with_fake_tools bash "$ROOT/scripts/zshrc-compat.sh" --migrate >"$tmp_root/tool-path-zshrc.out" 2>"$tmp_root/tool-path-zshrc.err"; then
  echo "FAIL: zshrc migrate failed under fake PATH tools" >&2
  cat "$tmp_root/tool-path-zshrc.out" >&2 || true
  cat "$tmp_root/tool-path-zshrc.err" >&2 || true
  exit 1
fi

for tool_name in awk diff grep; do
  if ! grep -Fqx "$tool_name" "$tool_path_log"; then
    echo "FAIL: expected PATH-resolved $tool_name wrapper was not used" >&2
    cat "$tool_path_log" >&2 || true
    exit 1
  fi
done

echo "PASS: sync cli common parse"
