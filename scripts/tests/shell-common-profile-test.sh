#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_SH="$ROOT/apps/shell/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/tests/shell-common-profile-test.sh

Description:
  Verifies that apps/shell/common.sh discovers profile bins and profile.d
  snippets in priority order for bash and zsh.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f $COMMON_SH ]]; then
  echo "test: common shell file not found: $COMMON_SH" >&2
  exit 1
fi

if grep -Eq '(brew.*shellenv|path_helper)' "$COMMON_SH"; then
  echo "FAIL: common.sh must not execute Homebrew or path_helper during shell startup" >&2
  exit 1
fi

bash_bin="${BASH_BIN:-$(command -v bash || true)}"
zsh_bin="${ZSH_BIN:-$(command -v zsh || true)}"
awk_bin="$(command -v awk || true)"

if [[ -z $bash_bin ]]; then
  echo "test: bash not found" >&2
  exit 1
fi
if [[ -z $zsh_bin ]]; then
  echo "test: zsh not found" >&2
  exit 1
fi
if [[ -z $awk_bin ]]; then
  echo "test: awk not found" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shell-common-profile.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

home_dir="$tmp_root/home"
primary_profile="$tmp_root/profiles/per-user/profiletest"
fallback_profile="$home_dir/.nix-profile"
fake_bin="$tmp_root/fake-bin"
runner="$tmp_root/source-common.sh"

mkdir -p \
  "$fake_bin" \
  "$primary_profile/bin" \
  "$primary_profile/etc/profile.d" \
  "$fallback_profile/bin" \
  "$fallback_profile/etc/profile.d"

cat >"$fake_bin/stty" <<EOF_FAKE_STTY
#!$bash_bin
set -euo pipefail
printf '%s\n' "\$*" >>"\$DOTFILES_TEST_STTY_LOG"
if [[ \${1:-} == echoctl ]]; then
  exit "\${DOTFILES_TEST_STTY_ECHOCTL_STATUS:-0}"
fi
exit 0
EOF_FAKE_STTY
chmod +x "$fake_bin/stty"

cat >"$fake_bin/uname" <<EOF_FAKE_UNAME
#!$bash_bin
set -euo pipefail
if [[ \${1:-} == -s ]]; then
  printf 'Darwin\n'
else
  printf 'Darwin\n'
fi
EOF_FAKE_UNAME
chmod +x "$fake_bin/uname"

cat >"$primary_profile/bin/nvim" <<'EOF_PRIMARY_NVIM'
#!/usr/bin/env bash
printf 'primary nvim\n'
EOF_PRIMARY_NVIM
chmod +x "$primary_profile/bin/nvim"

cat >"$fallback_profile/bin/nvim" <<'EOF_FALLBACK_NVIM'
#!/usr/bin/env bash
printf 'fallback nvim\n'
EOF_FALLBACK_NVIM
chmod +x "$fallback_profile/bin/nvim"

cat >"$fallback_profile/bin/fallback-only-tool" <<'EOF_FALLBACK_TOOL'
#!/usr/bin/env bash
printf 'fallback tool\n'
EOF_FALLBACK_TOOL
chmod +x "$fallback_profile/bin/fallback-only-tool"

cat >"$primary_profile/etc/profile.d/hm-session-vars.sh" <<'EOF_PRIMARY_HM'
if [ -n "$__HM_SESS_VARS_SOURCED" ]; then return; fi
export __HM_SESS_VARS_SOURCED=1
export DOTFILES_TEST_HM_PROFILE=primary
EOF_PRIMARY_HM

cat >"$fallback_profile/etc/profile.d/hm-session-vars.sh" <<'EOF_FALLBACK_HM'
if [ -n "$__HM_SESS_VARS_SOURCED" ]; then return; fi
export __HM_SESS_VARS_SOURCED=1
export DOTFILES_TEST_HM_PROFILE=fallback
EOF_FALLBACK_HM

cat >"$primary_profile/etc/profile.d/command-not-found.sh" <<'EOF_PRIMARY_CNF'
export DOTFILES_TEST_COMMAND_NOT_FOUND_PROFILE=primary
EOF_PRIMARY_CNF

cat >"$fallback_profile/etc/profile.d/command-not-found.sh" <<'EOF_FALLBACK_CNF'
export DOTFILES_TEST_COMMAND_NOT_FOUND_PROFILE=fallback
EOF_FALLBACK_CNF

cat >"$runner" <<'EOF_RUNNER'
set -u
source "$DOTFILES_TEST_COMMON_SH"
printf 'nvim=%s\n' "$(command -v nvim || true)"
printf 'fallback_only=%s\n' "$(command -v fallback-only-tool || true)"
printf 'hm=%s\n' "${DOTFILES_TEST_HM_PROFILE:-missing}"
printf 'command_not_found=%s\n' "${DOTFILES_TEST_COMMAND_NOT_FOUND_PROFILE:-missing}"
if dotfilesSetControlCharEcho; then
  printf 'stty_setter=ok\n'
else
  printf 'stty_setter=failed\n'
fi
if dotfilesSetStatusKey; then
  printf 'status_key_setter=ok\n'
else
  printf 'status_key_setter=failed\n'
fi
EOF_RUNNER
chmod +x "$runner"

base_path="$(dirname "$awk_bin")"

run_shell_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local output_file="$tmp_root/$shell_name.out"
  local stty_log="$tmp_root/$shell_name.stty.log"

  : >"$stty_log"

  if ! env -i \
    HOME="$home_dir" \
    USER=profiletest \
    DOTFILES_PROFILE_DIRS="$primary_profile" \
    DOTFILES_TEST_COMMON_SH="$COMMON_SH" \
    DOTFILES_TEST_STTY_ECHOCTL_STATUS=1 \
    DOTFILES_TEST_STTY_LOG="$stty_log" \
    PATH="$fake_bin:$base_path" \
    "$shell_bin" "$runner" >"$output_file"; then
    echo "FAIL: sourcing common.sh failed under $shell_name" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if ! grep -Fqx "nvim=$primary_profile/bin/nvim" "$output_file"; then
    echo "FAIL: $shell_name did not prefer the primary profile nvim" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if ! grep -Fqx "fallback_only=$fallback_profile/bin/fallback-only-tool" "$output_file"; then
    echo "FAIL: $shell_name did not expose fallback-only profile tools" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if ! grep -Fqx "hm=primary" "$output_file"; then
    echo "FAIL: $shell_name did not source hm-session-vars.sh from the primary profile" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if ! grep -Fqx "command_not_found=primary" "$output_file"; then
    echo "FAIL: $shell_name did not source command-not-found.sh from the primary profile" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if ! grep -Fqx "stty_setter=ok" "$output_file"; then
    echo "FAIL: $shell_name control-character echo setter failed" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if ! grep -Fqx "status_key_setter=ok" "$output_file"; then
    echo "FAIL: $shell_name status key setter failed" >&2
    cat "$output_file" >&2 || true
    exit 1
  fi

  if [[ $(cat "$stty_log") != $'echoctl\nctlecho\nstatus ^T kerninfo' ]]; then
    echo "FAIL: $shell_name did not configure control-character echo and status key" >&2
    cat "$stty_log" >&2 || true
    exit 1
  fi
}

printf 'test: running shell common profile test\n'
printf 'test: temp root = %s\n' "$tmp_root"

run_shell_case bash "$bash_bin"
run_shell_case zsh "$zsh_bin"

echo "PASS: shell common profile"
