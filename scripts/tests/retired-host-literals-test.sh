#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

if rg -n --fixed-strings "a2m_mac" . \
  --glob '!result/**' \
  --glob '!.direnv/**' \
  --glob '!.git/**' \
  --glob '!scripts/tests/retired-host-literals-test.sh'; then
  echo "FAIL: retired host literal a2m_mac is still present" >&2
  exit 1
fi

echo "PASS: retired host literals"
