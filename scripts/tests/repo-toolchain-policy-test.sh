#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLES_FILE="$ROOT/nix/catalog/darwin/bundles.nix"
HOSTS_FILE="$ROOT/nix/catalog/darwin/hosts.nix"
CATALOG_FILE="$ROOT/nix/catalog/tools/nixpkgs.nix"
HOMEBREW_OWNERSHIP_FILE="$ROOT/nix/catalog/tools/homebrew-ownership.nix"
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
require_file "$HOSTS_FILE"
require_file "$CATALOG_FILE"
require_file "$HOMEBREW_OWNERSHIP_FILE"
require_file "$README_FILE"
require_file "$README_JA_FILE"

require_not_contains "$BUNDLES_FILE" "tools.dev.go.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.nodejs.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.bun.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.opentofu.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.dev.terraform.enable = true;"
require_not_contains "$HOSTS_FILE" "dev.go.enable = true;"
require_not_contains "$HOSTS_FILE" "dev.nodejs.enable = true;"
require_not_contains "$HOSTS_FILE" "dev.opentofu.enable = true;"
require_not_contains "$HOSTS_FILE" "dev.terraform.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.downloadArchive.ytDlp.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.passwordSecrets.bw.enable = true;"
require_not_contains "$BUNDLES_FILE" "tools.passwordSecrets.rbw.enable = true;"

require_not_contains "$CATALOG_FILE" 'go = { group = "dev"; pkg = "go"; };'
require_not_contains "$CATALOG_FILE" 'nodejs = { group = "dev"; pkg = "nodejs"; };'
require_not_contains "$CATALOG_FILE" 'opentofu = { group = "dev"; pkg = "opentofu"; };'
require_not_contains "$CATALOG_FILE" 'pkg = "terraform";'
require_contains "$CATALOG_FILE" 'bun = { group = "dev"; pkg = "bun"; };'
require_not_contains "$CATALOG_FILE" 'pkg = "yt-dlp";'
require_not_contains "$CATALOG_FILE" 'pkg = "bitwarden-cli";'
require_not_contains "$CATALOG_FILE" 'pkg = "rbw";'
require_contains "$HOMEBREW_OWNERSHIP_FILE" "requiresFullXcode = true;"

require_contains "$README_FILE" 'Stock Darwin profiles and host overrides do not expose global opt-in toggles for `go`, `nodejs`, `opentofu`, or `terraform`'
require_contains "$README_FILE" '`bun` is the only project-pinned toolchain exception'
require_contains "$README_JA_FILE" 'stock Darwin profile と host override は `go`, `nodejs`, `opentofu`, `terraform` の global opt-in toggle を提供しません'
require_contains "$README_JA_FILE" '`bun` だけは project-pinned toolchain の例外'

echo "PASS: repo toolchain policy"
