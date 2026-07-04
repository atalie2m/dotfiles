#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HISTORY_ZSH="$ROOT/apps/shell/atuin-context-history.zsh"

if [[ ! -f $HISTORY_ZSH ]]; then
	echo "test: Atuin context history script not found: $HISTORY_ZSH" >&2
	exit 1
fi

zsh_bin="${ZSH_BIN:-$(command -v zsh || true)}"
bash_bin="${BASH_BIN:-$(command -v bash || true)}"

if [[ -z $zsh_bin ]]; then
	echo "test: zsh not found" >&2
	exit 1
fi
if [[ -z $bash_bin ]]; then
	echo "test: bash not found" >&2
	exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/atuin-context-history.XXXXXX")"
tmp_root="$(cd "$tmp_root" && pwd)"
cleanup() {
	rm -rf "$tmp_root"
}
trap cleanup EXIT

fake_bin="$tmp_root/bin"
home_dir="$tmp_root/home"
work_root="$tmp_root/work"
cwd="$work_root/repo/sub"
parent_one="$work_root/repo"
parent_two="$work_root"
state_dir="$tmp_root/state"
output_file="$tmp_root/candidates.out"
runner="$tmp_root/run.zsh"

mkdir -p "$fake_bin" "$home_dir" "$cwd" "$state_dir"

cat >"$fake_bin/atuin" <<EOF_FAKE_ATUIN
#!$bash_bin
set -euo pipefail

cwd_filter=""
filter_mode=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    search)
      shift
      ;;
    --cwd)
      cwd_filter="\$2"
      shift 2
      ;;
    --filter-mode)
      filter_mode="\$2"
      shift 2
      ;;
    --limit|--format)
      shift 2
      ;;
    --print0)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

emit() {
  printf '%s\t%s\0' "\$1" "\$2"
}

if [[ "\$cwd_filter" == "$cwd" ]]; then
  emit "$cwd" "current command"
elif [[ "\$filter_mode" == "workspace" ]]; then
  emit "$parent_one" "workspace command"
  emit "$parent_one" "current command"
elif [[ "\$cwd_filter" == "$parent_one" ]]; then
  emit "$parent_one" "parent one command"
elif [[ "\$cwd_filter" == "$parent_two" ]]; then
  emit "$parent_two" "parent two command"
elif [[ "\$filter_mode" == "global" ]]; then
  emit "/elsewhere" "global command"
  emit "/elsewhere" "parent one command"
fi
EOF_FAKE_ATUIN
chmod +x "$fake_bin/atuin"

cat >"$runner" <<'EOF_RUNNER'
set -e

cd "$DOTFILES_TEST_CWD"
source "$DOTFILES_TEST_HISTORY_ZSH"

DOTFILES_ATUIN_CONTEXT_PARENT_DEPTH=2 \
DOTFILES_ATUIN_CONTEXT_CURRENT_LIMIT=20 \
DOTFILES_ATUIN_CONTEXT_WORKSPACE_LIMIT=20 \
DOTFILES_ATUIN_CONTEXT_PARENT_LIMIT=20 \
DOTFILES_ATUIN_CONTEXT_GLOBAL_LIMIT=20 \
  _dotfiles_atuin_context_build_candidates "$DOTFILES_TEST_STATE_DIR" "" >"$DOTFILES_TEST_OUTPUT"
EOF_RUNNER

printf 'test: running Atuin context history test\n'
printf 'test: temp root = %s\n' "$tmp_root"

if ! env -i \
	HOME="$home_dir" \
	PATH="$fake_bin:/usr/bin:/bin" \
	DOTFILES_TEST_CWD="$cwd" \
	DOTFILES_TEST_HISTORY_ZSH="$HISTORY_ZSH" \
	DOTFILES_TEST_STATE_DIR="$state_dir" \
	DOTFILES_TEST_OUTPUT="$output_file" \
	"$zsh_bin" "$runner"; then
	echo "FAIL: zsh candidate builder failed" >&2
	exit 1
fi

expected_order=$'cwd\tcurrent command\nworkspace\tworkspace command\nparent:..\tparent one command\nparent:../..\tparent two command\nglobal\tglobal command'
actual_order="$(cut -f2,4 "$output_file")"
if [[ "$actual_order" != "$expected_order" ]]; then
	echo "FAIL: unexpected context history order" >&2
	echo "expected:" >&2
	printf '%s\n' "$expected_order" >&2
	echo "actual:" >&2
	printf '%s\n' "$actual_order" >&2
	exit 1
fi

if grep -Fq "duplicate command" "$output_file"; then
	echo "FAIL: duplicate lower-priority command leaked into candidates" >&2
	cat "$output_file" >&2
	exit 1
fi

if [[ $(cat "$state_dir/command-000003") != "parent one command" ]]; then
	echo "FAIL: raw command payload was not written by candidate id" >&2
	exit 1
fi

echo "PASS: Atuin context history"
