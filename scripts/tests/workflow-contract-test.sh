#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

if [[ ! -f $WORKFLOW ]]; then
  echo "FAIL: workflow not found: $WORKFLOW" >&2
  exit 1
fi

require_contains() {
  local expected="$1"
  if ! grep -Fq -- "$expected" "$WORKFLOW"; then
    echo "FAIL: workflow missing expected text: $expected" >&2
    exit 1
  fi
}

require_not_contains() {
  local forbidden="$1"
  if grep -Fq -- "$forbidden" "$WORKFLOW"; then
    echo "FAIL: workflow still contains forbidden text: $forbidden" >&2
    exit 1
  fi
}

require_contains "linux-hygiene:"
require_contains "darwin-contract:"
require_contains "targets-manifest.nix"
require_contains "host.buildTarget"
require_contains 'if host.defaultProfile == "minimal" then "ultra" else "minimal"'
require_contains 'host.targetsByProfile.${extraProfile}'
require_contains "Run target manifest test"
require_contains "Run template source hygiene test"

require_not_contains "homeConfigurations"
require_not_contains "nixosConfigurations"
require_not_contains "a2m_nixos"
require_not_contains "own_mac-minimum"
require_not_contains 'platform = "$PLATFORM"'
require_not_contains "planner: linux"
require_not_contains 'if [[ $target != *-* ]]; then'

if ! awk '
  /^  linux-hygiene:/ { in_linux = 1; next }
  /^  [A-Za-z0-9_-]+:/ && $0 !~ /^  linux-hygiene:/ { in_linux = 0 }
  in_linux && /nix / { found = 1 }
  END { exit found ? 1 : 0 }
' "$WORKFLOW"; then
  echo "FAIL: linux-hygiene job should not invoke nix" >&2
  exit 1
fi

echo "PASS: workflow contract"
