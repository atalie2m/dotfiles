#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: retired host literals test requires rg" >&2
  exit 1
fi

for retired_host in a2m_mac pro_mac ultra_mac minimal_mac; do
  if rg -n --fixed-strings "$retired_host" . \
    --glob '!result/**' \
    --glob '!.direnv/**' \
    --glob '!.git/**' \
    --glob '!scripts/tests/retired-host-literals-test.sh'; then
    echo "FAIL: retired host literal $retired_host is still present" >&2
    exit 1
  fi
done

echo "PASS: retired host literals"
