#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPORT_SCRIPT="$ROOT/scripts/export-clean.sh"
DOTFILES_SCRIPT="$ROOT/scripts/dotfiles.sh"

if [[ ! -f $EXPORT_SCRIPT ]]; then
  echo "test: export-clean script not found: $EXPORT_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $DOTFILES_SCRIPT ]]; then
  echo "test: dotfiles script not found: $DOTFILES_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/export-clean.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

dir_output="$tmp_root/export-dir"
tar_output="$tmp_root/export.tar"
tar_list="$tmp_root/export.tar.list"

if ! bash "$EXPORT_SCRIPT" --format dir --output "$dir_output" >/dev/null; then
  echo "FAIL: directory export failed" >&2
  exit 1
fi

if [[ ! -f "$dir_output/flake.nix" ]]; then
  echo "FAIL: directory export is missing flake.nix" >&2
  exit 1
fi

for forbidden in ".git" ".DS_Store" "result"; do
  if [[ -e "$dir_output/$forbidden" ]]; then
    echo "FAIL: directory export unexpectedly included $forbidden" >&2
    exit 1
  fi
done

if find "$dir_output" -name '._*' -print -quit | grep -q .; then
  echo "FAIL: directory export unexpectedly included AppleDouble files" >&2
  exit 1
fi

if ! bash "$DOTFILES_SCRIPT" export-clean --format dir --output "$tmp_root/export-via-dotfiles" >/dev/null; then
  echo "FAIL: dotfiles export-clean delegation failed" >&2
  exit 1
fi

if ! bash "$EXPORT_SCRIPT" --format tar --output "$tar_output" >/dev/null; then
  echo "FAIL: tar export failed" >&2
  exit 1
fi

tar -tf "$tar_output" >"$tar_list"

if ! grep -Fq "flake.nix" "$tar_list"; then
  echo "FAIL: tar export is missing flake.nix" >&2
  cat "$tar_list" >&2 || true
  exit 1
fi

if grep -E '(^|/)(\.git|\.DS_Store|result)(/|$)' "$tar_list" >/dev/null; then
  echo "FAIL: tar export unexpectedly included ignored metadata" >&2
  cat "$tar_list" >&2 || true
  exit 1
fi

if grep -E '(^|/)\\._[^/]+$' "$tar_list" >/dev/null; then
  echo "FAIL: tar export unexpectedly included AppleDouble files" >&2
  cat "$tar_list" >&2 || true
  exit 1
fi

fake_git_dir="$tmp_root/fake-git"
mkdir -p "$fake_git_dir"

cat >"$fake_git_dir/git-missing" <<EOF
#!${BASH:-bash}
echo "git: command not found" >&2
exit 127
EOF
chmod +x "$fake_git_dir/git-missing"

cat >"$fake_git_dir/git-refused" <<EOF
#!${BASH:-bash}
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
  echo "fatal: detected dubious ownership in repository at '$ROOT'" >&2
  exit 128
fi
echo "fatal: detected dubious ownership in repository at '$ROOT'" >&2
exit 128
EOF
chmod +x "$fake_git_dir/git-refused"

assert_export_fails() {
  local expected="$1"
  local wrapper="$2"
  local stderr_file="$tmp_root/$wrapper.err"
  local path_dir="$tmp_root/path-$wrapper"

  mkdir -p "$path_dir"
  ln -sf "$fake_git_dir/$wrapper" "$path_dir/git"

  if PATH="$path_dir:$PATH" bash "$EXPORT_SCRIPT" --format dir --output "$tmp_root/$wrapper-output" >"$tmp_root/$wrapper.out" 2>"$stderr_file"; then
    echo "FAIL: export-clean unexpectedly succeeded with git wrapper $wrapper" >&2
    exit 1
  fi

  if ! grep -Fq "$expected" "$stderr_file"; then
    echo "FAIL: export-clean error message missing expected text for $wrapper" >&2
    cat "$stderr_file" >&2 || true
    exit 1
  fi
}

assert_export_fails "requires a trusted Git worktree" "git-missing"
assert_export_fails "detected dubious ownership" "git-refused"

echo "PASS: export clean smoke"
