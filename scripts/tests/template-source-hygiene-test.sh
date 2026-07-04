#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

require_file() {
  local path="$1"
  if [[ ! -f $path ]]; then
    echo "FAIL: expected file missing: $path" >&2
    exit 1
  fi
}

require_contains() {
  local path="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$path"; then
    echo "FAIL: expected text missing from $path: $expected" >&2
    exit 1
  fi
}

template_count=0
while IFS= read -r template_dir; do
  template_count=$((template_count + 1))
  require_file "$template_dir/flake.nix"
  require_file "$template_dir/.envrc"
  require_file "$template_dir/.gitignore"
  require_file "$template_dir/AGENTS.md"

  require_contains "$template_dir/.envrc" "use flake"

  for ignored in "target/" "node_modules/" ".git/" ".direnv/"; do
    require_contains "$template_dir/.gitignore" "$ignored"
  done

  require_contains "$template_dir/AGENTS.md" 'nix run path:$PWD#...'
  require_contains "$template_dir/AGENTS.md" 'nix build path:$PWD#...'
  require_contains "$template_dir/AGENTS.md" 'nix run .#...'
  require_contains "$template_dir/AGENTS.md" 'nix build .#...'
  require_contains "$template_dir/AGENTS.md" 'target/`, `node_modules/`, `.git/`, and `.direnv/`'
  require_contains "$template_dir/AGENTS.md" 'nix store gc --dry-run'
  require_contains "$template_dir/AGENTS.md" 'sudo nix-collect-garbage -d'
  require_contains "$template_dir/AGENTS.md" 'source evaluation guard'
  require_contains "$template_dir/AGENTS.md" 'checks.flake-source-hygiene'

  require_contains "$template_dir/flake.nix" 'unsafeFlakeSource'
  require_contains "$template_dir/flake.nix" 'Refusing to evaluate this flake because target/, node_modules/, .git/, or .direnv/ is present in the flake source.'
  require_contains "$template_dir/flake.nix" 'checks.flake-source-hygiene'
  require_contains "$template_dir/flake.nix" 'for dir in target node_modules .git .direnv; do'

  if grep -Fq -- 'path:$PWD' "$template_dir/.envrc"; then
    echo "FAIL: .envrc must not use path:\$PWD in $template_dir" >&2
    exit 1
  fi
done < <(find templates -mindepth 1 -maxdepth 1 -type d | sort)

if [[ $template_count -eq 0 ]]; then
  echo "FAIL: no templates found" >&2
  exit 1
fi

echo "PASS: template source hygiene"
