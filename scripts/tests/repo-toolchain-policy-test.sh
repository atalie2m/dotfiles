#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLES_FILE="$ROOT/nix/catalog/darwin/bundles.nix"
README_FILE="$ROOT/README.md"
README_JA_FILE="$ROOT/docs/ja/README.md"

require_file() {
  local path="$1"
  if [[ ! -f $path ]]; then
    echo "FAIL: expected file missing: $path" >&2
    exit 1
  fi
}

require_not_contains() {
  local path="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$path"; then
    echo "FAIL: unexpected global toolchain enablement in $path: $forbidden" >&2
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

require_file "$BUNDLES_FILE"
require_file "$README_FILE"
require_file "$README_JA_FILE"

require_not_contains "$BUNDLES_FILE" "tools.dev.go.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.nodejs.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.opentofu.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.terraform.enable = true;"

require_contains "$README_FILE" 'Stock Darwin profiles leave `go`, `nodejs`, `opentofu`, and `terraform` to project templates/devShells'
require_contains "$README_JA_FILE" 'stock Darwin profile は `go`, `nodejs`, `opentofu`, `terraform` を project template/devShell に残します'

echo "PASS: repo toolchain policy"
