#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"
TEMPLATES_WORKFLOW="$ROOT/.github/workflows/flake-templates.yml"

for workflow in "$WORKFLOW" "$TEMPLATES_WORKFLOW"; do
  if [[ ! -f $workflow ]]; then
    echo "FAIL: workflow not found: $workflow" >&2
    exit 1
  fi
done

require_contains() {
  local workflow="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$workflow"; then
    echo "FAIL: $(basename "$workflow") missing expected text: $expected" >&2
    exit 1
  fi
}

require_not_contains() {
  local workflow="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$workflow"; then
    echo "FAIL: $(basename "$workflow") still contains forbidden text: $forbidden" >&2
    exit 1
  fi
}

require_event_branches() {
  local workflow="$1"
  local event_name="$2"
  local expected=$'main\nmaint/**\nstabilize/**'
  local actual

  actual=$(
    awk -v event_name="$event_name" '
      $0 == "  " event_name ":" { in_event = 1; next }
      in_event && /^  [[:alnum:]_-]+:/ { exit }
      in_event && /^    branches:/ { in_branches = 1; next }
      in_branches && /^      - / {
        value = $0
        sub(/^      -[[:space:]]*/, "", value)
        gsub("\"", "", value)
        gsub("\047", "", value)
        print value
        next
      }
      in_branches && $0 !~ /^[[:space:]]*$/ { exit }
    ' "$workflow"
  )

  if [[ $actual != "$expected" ]]; then
    echo "FAIL: $(basename "$workflow") $event_name branches differ" >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

require_job_contains() {
  local workflow="$1"
  local job_name="$2"
  local expected="$3"

  if ! awk -v job_name="$job_name" -v expected="$expected" '
    $0 == "  " job_name ":" { in_job = 1; next }
    in_job && /^  [[:alnum:]_-]+:/ { exit }
    in_job && index($0, expected) { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$workflow"; then
    echo "FAIL: $(basename "$workflow") job $job_name missing expected text: $expected" >&2
    exit 1
  fi
}

for workflow in "$WORKFLOW" "$TEMPLATES_WORKFLOW"; do
  require_contains "$workflow" "  workflow_dispatch:"
  require_event_branches "$workflow" "push"
  require_event_branches "$workflow" "pull_request"
  require_contains "$workflow" "  cancel-in-progress: true"
done

# shellcheck disable=SC2016 # GitHub expressions are matched literally.
require_contains "$WORKFLOW" '  group: ci-${{ github.workflow }}-${{ github.ref }}'
# shellcheck disable=SC2016 # GitHub expressions are matched literally.
require_contains "$TEMPLATES_WORKFLOW" '  group: templates-${{ github.workflow }}-${{ github.ref }}'
require_job_contains "$WORKFLOW" "linux-hygiene" "    timeout-minutes: 15"
require_job_contains "$WORKFLOW" "darwin-contract" "    timeout-minutes: 45"
require_job_contains "$TEMPLATES_WORKFLOW" "templates-flake-check" "    timeout-minutes: 30"

require_contains "$WORKFLOW" "linux-hygiene:"
require_contains "$WORKFLOW" "darwin-contract:"
require_contains "$WORKFLOW" "targets-manifest.nix"
require_contains "$WORKFLOW" "host.buildTarget"
require_contains "$WORKFLOW" 'if host.defaultProfile == "minimal" then "ultra" else "minimal"'
require_contains "$WORKFLOW" 'host.targetsByProfile.${extraProfile}'
require_contains "$WORKFLOW" "Run target manifest test"
require_contains "$WORKFLOW" "Run template source hygiene test"

require_not_contains "$WORKFLOW" "homeConfigurations"
require_not_contains "$WORKFLOW" "nixosConfigurations"
require_not_contains "$WORKFLOW" "a2m_nixos"
require_not_contains "$WORKFLOW" "own_mac-minimum"
require_not_contains "$WORKFLOW" 'platform = "$PLATFORM"'
require_not_contains "$WORKFLOW" "planner: linux"
require_not_contains "$WORKFLOW" 'if [[ $target != *-* ]]; then'

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
