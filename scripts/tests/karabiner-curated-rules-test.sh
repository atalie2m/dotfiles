#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: karabiner curated rules test requires jq" >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: karabiner curated rules test requires rg" >&2
  exit 1
fi

curated_files=(
  "$ROOT/keyboards/karabiner/complex_modifications/curated-standard.json"
  "$ROOT/keyboards/karabiner/complex_modifications/curated-a2m.json"
)

for file in "${curated_files[@]}"; do
  if [[ ! -f $file ]]; then
    echo "FAIL: curated file missing: $file" >&2
    exit 1
  fi

  if ! jq -e '.rules and (.rules | type == "array") and ((.rules | length) > 0)' "$file" >/dev/null; then
    echo "FAIL: curated file has invalid or empty rules array: $file" >&2
    exit 1
  fi

done

if rg -n "specificRulesFrom|rule\.description|descriptions" "$ROOT/nix/modules/tools/system/karabiner.nix"; then
  echo "FAIL: karabiner module still depends on description-based selection" >&2
  exit 1
fi

echo "PASS: karabiner curated rules"
