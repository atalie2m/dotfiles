#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_SCRIPT="$ROOT/scripts/atalie-tar"

if [[ ! -f $ARCHIVE_SCRIPT ]]; then
  echo "test: archive script not found: $ARCHIVE_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/atalie-tar.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

repo="$tmp_root/repo"
mkdir -p "$repo/build" "$repo/node_modules/pkg"

git -C "$repo" init -q
git -C "$repo" config user.name "Dotfiles Test"
git -C "$repo" config user.email "dotfiles@example.com"

cat >"$repo/.gitignore" <<'EOF'
build/
node_modules/
EOF

printf 'tracked\n' >"$repo/tracked.txt"
printf 'notes\n' >"$repo/notes.txt"
printf 'ignored\n' >"$repo/build/output.txt"
printf 'ignored\n' >"$repo/node_modules/pkg/index.js"
printf 'ignored\n' >"$repo/.DS_Store"
mkdir -p "$repo/src"
printf 'ignored\n' >"$repo/src/.DS_Store"

git -C "$repo" add .gitignore tracked.txt
git -C "$repo" commit -q -m "init"

archive="$tmp_root/repo.tar.gz"
archive_list="$tmp_root/repo.tar.list"
archive_outside="$tmp_root/repo-nested/archive.tar.gz"
repo_name="$(basename "$repo")"

pushd "$repo" >/dev/null

if ! bash "$ARCHIVE_SCRIPT" --gitignore -czf "$archive" -C .. "$repo_name" >/dev/null; then
  echo "FAIL: archive helper failed" >&2
  popd >/dev/null
  exit 1
fi

popd >/dev/null

tar -tzf "$archive" >"$archive_list"

for expected in "$repo_name/.gitignore" "$repo_name/tracked.txt" "$repo_name/notes.txt"; do
  if ! grep -Fqx -- "$expected" "$archive_list"; then
    echo "FAIL: archive missing expected file: $expected" >&2
    cat "$archive_list" >&2 || true
    exit 1
  fi
done

for forbidden in "$repo_name/build/output.txt" "$repo_name/node_modules/pkg/index.js" "$repo_name/.DS_Store" "$repo_name/src/.DS_Store" "$repo_name/.git"; do
  if grep -Fqx -- "$forbidden" "$archive_list"; then
    echo "FAIL: archive unexpectedly included ignored file: $forbidden" >&2
    cat "$archive_list" >&2 || true
    exit 1
  fi
done

inside_stderr="$tmp_root/inside.err"
pushd "$repo" >/dev/null
if bash "$ARCHIVE_SCRIPT" --gitignore -czf "$repo/inside.tar.gz" -C .. "$repo_name" >"$tmp_root/inside.out" 2>"$inside_stderr"; then
  echo "FAIL: archive helper unexpectedly allowed an in-repo output path" >&2
  popd >/dev/null
  exit 1
fi
popd >/dev/null

if ! grep -Fq "output must be outside the repository root" "$inside_stderr"; then
  echo "FAIL: missing output path guard message" >&2
  cat "$inside_stderr" >&2 || true
  exit 1
fi

pushd "$repo" >/dev/null
if ! bash "$ARCHIVE_SCRIPT" --gitignore -czf "$archive_outside" -C .. "$repo_name" >/dev/null 2>&1; then
  # The parent dir is missing on purpose; the script should create it.
  popd >/dev/null
  echo "FAIL: archive helper should create the output directory" >&2
  exit 1
fi
popd >/dev/null

if [[ ! -f $archive_outside ]]; then
  echo "FAIL: archive helper did not create nested output archive" >&2
  exit 1
fi

echo "PASS: atalie-tar smoke"
