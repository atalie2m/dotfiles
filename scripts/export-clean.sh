#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="export-clean"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/export-clean.sh --output <path> [--format dir|tar]

Exports the current git-tracked working tree without .git metadata or macOS
AppleDouble sidecar files. The output path must not already exist.
USAGE
}

format="dir"
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --output)
    shift
    [[ $# -gt 0 ]] || die "missing value for --output"
    output="$1"
    ;;
  --format)
    shift
    [[ $# -gt 0 ]] || die "missing value for --format"
    format="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
  shift
done

case "$format" in
dir | tar) ;;
*) die "invalid --format: $format (expected dir or tar)" ;;
esac

[[ -n $output ]] || die "--output is required"

set_repo_root
cd "$ROOT"

if [[ -e $output ]]; then
  die "output already exists: $output"
fi

mkdir -p "$(dirname "$output")"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-export.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

export_root="$tmp_root/export"
mkdir -p "$export_root"

while IFS= read -r -d '' relpath; do
  src="$ROOT/$relpath"
  dest="$export_root/$relpath"

  [[ -e $src || -L $src ]] || die "tracked path is missing from the working tree: $relpath"

  mkdir -p "$(dirname "$dest")"
  cp -pP "$src" "$dest"
done < <(
  if git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$ROOT" ls-files -z
  else
    find . \
      \( -name .git -o -name .DS_Store -o -name result -o -name '._*' \) -prune \
      -o \( -type f -o -type l \) -print0
  fi
)

case "$format" in
dir)
  mv "$export_root" "$output"
  ;;
tar)
  COPYFILE_DISABLE=1 tar -C "$export_root" -cf "$output" .
  ;;
esac
