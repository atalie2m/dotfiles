#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOTFILES_SCRIPT="$ROOT/nix/scripts/dotfiles.sh"
SYNC_SCRIPT="$ROOT/nix/scripts/sync.sh"
UPDATE_SCRIPT="$ROOT/nix/scripts/update.sh"

if [[ ! -f $DOTFILES_SCRIPT ]]; then
  echo "test: dotfiles script not found: $DOTFILES_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $SYNC_SCRIPT ]]; then
  echo "test: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

if [[ ! -f $UPDATE_SCRIPT ]]; then
  echo "test: update script not found: $UPDATE_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/sync-cli-migration.XXXXXX")"
tmp_stdout="$tmp_root/stdout"
tmp_stderr="$tmp_root/stderr"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

if bash "$DOTFILES_SCRIPT" shell sync --check >"$tmp_stdout" 2>"$tmp_stderr"; then
  echo "FAIL: legacy shell CLI unexpectedly succeeded" >&2
  exit 1
fi

if ! grep -Fq 'unknown subcommand: shell' "$tmp_stderr"; then
  echo "FAIL: legacy shell CLI did not report unknown subcommand" >&2
  cat "$tmp_stderr" >&2 || true
  exit 1
fi

if ! grep -Fq 'sync' "$tmp_stderr"; then
  echo "FAIL: legacy shell CLI error did not point to new sync command" >&2
  cat "$tmp_stderr" >&2 || true
  exit 1
fi

help_output="$(bash "$SYNC_SCRIPT" --help 2>&1 || true)"
if [[ $help_output != *"sync shell"* ]]; then
  echo "FAIL: sync help missing shell usage" >&2
  printf '%s\n' "$help_output" >&2
  exit 1
fi
if [[ $help_output == *"terminal --check"* ]]; then
  echo "FAIL: sync help still advertises removed terminal surface" >&2
  printf '%s\n' "$help_output" >&2
  exit 1
fi

fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/nix" <<'EOF_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 2 && $1 == "flake" && $2 == "update" ]]; then
  if [[ -n ${FAKE_FLAKE_LOCK_CONTENT:-} ]]; then
    printf '%s\n' "$FAKE_FLAKE_LOCK_CONTENT" > flake.lock
  fi
  exit 0
fi

echo "fake nix: unexpected invocation: $*" >&2
exit 1
EOF_NIX
chmod +x "$fake_bin/nix"

setup_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init --quiet
  git -C "$repo_dir" config user.name "Dotfiles Test"
  git -C "$repo_dir" config user.email "dotfiles@example.invalid"

  printf '{ description = "test flake"; }\n' >"$repo_dir/flake.nix"
  printf '{ "version": 1 }\n' >"$repo_dir/flake.lock"
  printf 'tracked baseline\n' >"$repo_dir/unrelated.txt"

  git -C "$repo_dir" add flake.nix flake.lock unrelated.txt
  git -C "$repo_dir" commit -m "init" --quiet
}

run_update() {
  local repo_dir="$1"
  local stdout_file="$2"
  local stderr_file="$3"

  shift 3

  (
    export HOME="$tmp_root/home"
    export PATH="$fake_bin:$PATH"
    export DOTFILES_ROOT="$repo_dir"
    export UPDATE_SKIP_CHECK=1
    export UPDATE_SKIP_BUILD=1
    export UPDATE_COMMIT=1
    mkdir -p "$HOME"

    while [[ $# -gt 0 ]]; do
      export "${1%%=*}=${1#*=}"
      shift
    done

    bash "$UPDATE_SCRIPT" --host a2m_mac
  ) >"$stdout_file" 2>"$stderr_file"
}

commit_repo="$tmp_root/commit-repo"
setup_repo "$commit_repo"
printf 'staged but unrelated\n' >"$commit_repo/unrelated.txt"
git -C "$commit_repo" add unrelated.txt

if ! run_update "$commit_repo" "$tmp_root/commit.stdout" "$tmp_root/commit.stderr" 'FAKE_FLAKE_LOCK_CONTENT={ "version": 2 }'; then
  echo "FAIL: update commit flow failed" >&2
  cat "$tmp_root/commit.stdout" >&2 || true
  cat "$tmp_root/commit.stderr" >&2 || true
  exit 1
fi

commit_files="$(git -C "$commit_repo" diff-tree --no-commit-id --name-only -r HEAD)"
if [[ $commit_files != "flake.lock" ]]; then
  echo "FAIL: update commit included unexpected files: $commit_files" >&2
  exit 1
fi

if ! git -C "$commit_repo" diff --cached --name-only | grep -Fqx "unrelated.txt"; then
  echo "FAIL: unrelated staged change was not preserved outside the flake.lock commit" >&2
  git -C "$commit_repo" status --short >&2 || true
  exit 1
fi

noop_repo="$tmp_root/noop-repo"
setup_repo "$noop_repo"
printf 'still unrelated\n' >"$noop_repo/unrelated.txt"
git -C "$noop_repo" add unrelated.txt

if ! run_update "$noop_repo" "$tmp_root/noop.stdout" "$tmp_root/noop.stderr"; then
  echo "FAIL: update noop flow failed" >&2
  cat "$tmp_root/noop.stdout" >&2 || true
  cat "$tmp_root/noop.stderr" >&2 || true
  exit 1
fi

if ! grep -Fq "update: no flake.lock changes to commit" "$tmp_root/noop.stdout"; then
  echo "FAIL: update noop flow did not report flake.lock-specific no-op" >&2
  cat "$tmp_root/noop.stdout" >&2 || true
  exit 1
fi

if [[ $(git -C "$noop_repo" rev-list --count HEAD) != "1" ]]; then
  echo "FAIL: noop update unexpectedly created a commit" >&2
  git -C "$noop_repo" log --oneline >&2 || true
  exit 1
fi

echo "PASS: sync CLI migration"
