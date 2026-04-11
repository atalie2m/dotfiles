#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: atalie-tar.sh [--gitignore] [--repo PATH] [-czf ARCHIVE -C PARENT REPO]

Create a tar.gz archive from a Git worktree while honoring gitignore rules
and always excluding macOS .DS_Store files.
The common tar-style call is:
  atalie-tar.sh --gitignore -czf ../<repo>-YYYYMMDD-HHMM.tar.gz -C .. <repo>

Options:
  --gitignore    Explicitly archive tracked + non-ignored files
  --repo PATH    Git worktree to archive (default: current directory)
  --output PATH  Archive output path
  -h, --help     Show this help
EOF
}

repo="."
output=""
gitignore_mode=1
parent_dir=""
repo_arg=""
repo_explicit=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitignore|-gitignore)
      gitignore_mode=1
      shift
      ;;
    --repo)
      if [[ $# -lt 2 ]]; then
        echo "atalie-tar: missing value for --repo" >&2
        exit 1
      fi
      repo="$2"
      repo_explicit=1
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        echo "atalie-tar: missing value for --output" >&2
        exit 1
      fi
      output="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -C)
      if [[ $# -lt 2 ]]; then
        echo "atalie-tar: missing value for -C" >&2
        exit 1
      fi
      parent_dir="$2"
      shift 2
      ;;
    -c|-z|-v)
      shift
      ;;
    -f)
      if [[ $# -lt 2 ]]; then
        echo "atalie-tar: missing archive path after -f" >&2
        exit 1
      fi
      output="$2"
      shift 2
      ;;
    -*f*)
      if [[ $# -lt 2 ]]; then
        echo "atalie-tar: missing archive path after $1" >&2
        exit 1
      fi
      output="$2"
      shift 2
      ;;
    -*)
      echo "atalie-tar: unsupported flag: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$repo_arg" ]]; then
        echo "atalie-tar: too many positional repository arguments" >&2
        usage >&2
        exit 1
      fi
      repo_arg="$1"
      shift
      ;;
  esac
done

if [[ -n "$repo_arg" ]]; then
  if [[ $repo_explicit -eq 1 ]]; then
    echo "atalie-tar: do not combine --repo with positional repository arguments" >&2
    exit 1
  fi

  if [[ -n "$parent_dir" ]]; then
    repo="${parent_dir%/}/$repo_arg"
  else
    repo="$repo_arg"
  fi
fi

if ! root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "atalie-tar: requires a Git worktree with a working git binary" >&2
  exit 1
fi

repo_name="$(basename "$root")"
if [[ -z "$output" ]]; then
  output="$(dirname "$root")/${repo_name}-$(date '+%Y%m%d-%H%M').tar.gz"
fi

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
output_abs="$(cd "$output_dir" && pwd -P)/$(basename "$output")"

case "$output_abs" in
  "$root"|"$root"/*)
    echo "atalie-tar: output must be outside the repository root: $output_abs" >&2
    exit 1
    ;;
esac

if [[ $gitignore_mode -ne 1 ]]; then
  echo "atalie-tar: unsupported mode" >&2
  exit 1
fi

parent_dir="$(dirname "$root")"
COPYFILE_DISABLE=1 git -C "$root" ls-files -co --exclude-standard -z \
  | while IFS= read -r -d '' relative; do
      case "$relative" in
        .DS_Store|*/.DS_Store)
          continue
          ;;
      esac
      printf '%s/%s\0' "$repo_name" "$relative"
    done \
  | COPYFILE_DISABLE=1 tar -C "$parent_dir" --null -czf "$output_abs" -T -

printf '%s\n' "$output_abs"
