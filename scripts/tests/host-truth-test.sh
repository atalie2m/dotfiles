#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: host truth test requires rg" >&2
  exit 1
fi

if rg -n 'config\.host\.' nix scripts crates --glob '!scripts/tests/**'; then
  echo "FAIL: direct config.host.* reads are forbidden; use myconfig.hostContext.*" >&2
  exit 1
fi

if rg -n 'config\.facts|myconfig\.facts' nix scripts crates --glob '!scripts/tests/**'; then
  echo "FAIL: direct facts reads are forbidden; use myconfig.hostContext.*" >&2
  exit 1
fi

matches="$(
  rg -n 'import \(inputs\.local \+ "/facts\.nix"\)|inputs\.local \+ "/facts\.nix"|rawFacts = import' nix scripts crates --glob '!scripts/tests/**' |
    grep -v '^nix/flake/configurations.nix:' |
    grep -v '^nix/denix/lib/mk-darwin-host.nix:' ||
    true
)"

if [[ -n $matches ]]; then
  echo "FAIL: raw facts import escaped the approved boundary" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "PASS: host truth"
