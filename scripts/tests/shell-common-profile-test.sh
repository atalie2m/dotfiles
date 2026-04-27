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
runner="$tmp_root/source-common.sh"

mkdir -p \
  "$primary_profile/bin" \
  "$primary_profile/etc/profile.d" \
  "$fallback_profile/bin" \
  "$fallback_profile/etc/profile.d"

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
export DOTFILES_TEST_HM_PROFILE=primary
EOF_PRIMARY_HM

cat >"$fallback_profile/etc/profile.d/hm-session-vars.sh" <<'EOF_FALLBACK_HM'
export DOTFILES_TEST_HM_PROFILE=fallback
EOF_FALLBACK_HM

cat >"$primary_profile/etc/profile.d/command-not-found.sh" <<'EOF_PRIMARY_CNF'
export DOTFILES_TEST_COMMAND_NOT_FOUND_PROFILE=primary
EOF_PRIMARY_CNF

cat >"$fallback_profile/etc/profile.d/command-not-found.sh" <<'EOF_FALLBACK_CNF'
export DOTFILES_TEST_COMMAND_NOT_FOUND_PROFILE=fallback
EOF_FALLBACK_CNF

cat >"$runner" <<'EOF_RUNNER'
source "$DOTFILES_TEST_COMMON_SH"
printf 'nvim=%s\n' "$(command -v nvim || true)"
printf 'fallback_only=%s\n' "$(command -v fallback-only-tool || true)"
printf 'hm=%s\n' "${DOTFILES_TEST_HM_PROFILE:-missing}"
printf 'command_not_found=%s\n' "${DOTFILES_TEST_COMMAND_NOT_FOUND_PROFILE:-missing}"
EOF_RUNNER
chmod +x "$runner"

base_path="$(dirname "$awk_bin")"

run_shell_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local output_file="$tmp_root/$shell_name.out"

  if ! env -i \
    HOME="$home_dir" \
    USER=profiletest \
    DOTFILES_PROFILE_DIRS="$primary_profile" \
    DOTFILES_TEST_COMMON_SH="$COMMON_SH" \
    PATH="$base_path" \
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
}

printf 'test: running shell common profile test\n'
printf 'test: temp root = %s\n' "$tmp_root"

run_shell_case bash "$bash_bin"
run_shell_case zsh "$zsh_bin"

echo "PASS: shell common profile"
