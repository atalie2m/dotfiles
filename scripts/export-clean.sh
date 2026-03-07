#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SCRIPT_LABEL="export-clean"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
source "$SCRIPT_DIR/lib/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/export-clean.sh --output <path> [--format dir|tar]
       nix run .#dotfiles -- export-clean --output <path> [--format dir|tar]

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

git_bin="$(command -v git 2>/dev/null || true)"
[[ -n $git_bin ]] || die "git is required for export-clean"

git_check_err="$tmp_root/git-check.err"
tracked_paths_file="$tmp_root/tracked-paths.zlist"

if ! "$git_bin" -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>"$git_check_err"; then
  git_check_message="$(tr '\n' ' ' <"$git_check_err" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  [[ -n $git_check_message ]] || git_check_message="git could not access the repository"
  die "export-clean requires a trusted Git worktree with a working git binary: $git_check_message"
fi

if ! "$git_bin" -C "$ROOT" ls-files -z >"$tracked_paths_file" 2>"$git_check_err"; then
  git_check_message="$(tr '\n' ' ' <"$git_check_err" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  [[ -n $git_check_message ]] || git_check_message="git could not enumerate tracked files"
  die "export-clean failed to enumerate tracked files: $git_check_message"
fi

while IFS= read -r -d '' relpath; do
  src="$ROOT/$relpath"
  dest="$export_root/$relpath"

  [[ -e $src || -L $src ]] || die "tracked path is missing from the working tree: $relpath"

  mkdir -p "$(dirname "$dest")"
  cp -pP "$src" "$dest"
done <"$tracked_paths_file"

case "$format" in
dir)
  mv "$export_root" "$output"
  ;;
tar)
  COPYFILE_DISABLE=1 tar -C "$export_root" -cf "$output" .
  ;;
esac
