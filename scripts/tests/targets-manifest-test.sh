#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"

flake_ref="path:$ROOT"

if ! command -v nix >/dev/null 2>&1; then
  echo "FAIL: target manifest test requires nix" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: target manifest test requires jq" >&2
  exit 1
fi

manifest_json="$(
  nix eval --json "${flake_ref}#darwinConfigurations" \
    --impure \
    --apply 'targets: (import ./nix/scripts/targets-manifest.nix {}).json targets'
)"

target_metadata_json="$(
  nix eval --json "${flake_ref}#darwinConfigurations" \
    --impure \
    --apply '
      targets:
        builtins.listToAttrs
          (map
            (target: {
              name = target;
              value = {
                host = targets.${target}.config.myconfig.hostContext.name;
                rice = targets.${target}.config.myconfig.rice.name;
              };
            })
            (builtins.attrNames targets))
    '
)"

if ! printf '%s' "$manifest_json" | jq -e '.hosts | type == "object" and length > 0' >/dev/null; then
  echo "FAIL: target manifest is empty or malformed" >&2
  exit 1
fi

if ! printf '%s' "$manifest_json" | jq -e '.hosts | to_entries | all(.[]; (.value.supportedRices | sort) == (.value.targetsByRice | keys | sort))' >/dev/null; then
  echo "FAIL: supportedRices does not match targetsByRice keys" >&2
  exit 1
fi

if ! printf '%s' "$manifest_json" | jq -e '.hosts | to_entries | all(.[]; .value.targetsByRice[.value.defaultRice] == .value.buildTarget)' >/dev/null; then
  echo "FAIL: targetsByRice.defaultRice must equal buildTarget for every host" >&2
  exit 1
fi

if ! jq -n --argjson manifest "$manifest_json" --argjson metadata "$target_metadata_json" -e '
  def manifestTargets:
    ([ $manifest.hosts
      | to_entries[]
      | .value
      | [ .buildTarget, (.targetsByRice | to_entries[] | .value) ]
    ] | flatten | unique | sort);
  def actualTargets:
    ($metadata | keys | sort);
  manifestTargets == actualTargets
' >/dev/null; then
  echo "FAIL: manifest target set does not exactly match darwinConfigurations attrNames" >&2
  exit 1
fi

while IFS=$'\t' read -r host default_rice build_target; do
  if ! grep -Fq "\`${host}\` (default rice: \`${default_rice}\`)" docs/commands.md; then
    echo "FAIL: docs/commands.md is missing host/default-rice pair for $host" >&2
    exit 1
  fi

  actual_host="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$build_target" '.[$target].host')"
  actual_rice="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$build_target" '.[$target].rice')"

  if [[ $actual_host != "$host" ]]; then
    echo "FAIL: buildTarget $build_target resolved host $actual_host, expected $host" >&2
    exit 1
  fi

  if [[ $actual_rice != "$default_rice" ]]; then
    echo "FAIL: buildTarget $build_target resolved rice $actual_rice, expected $default_rice" >&2
    exit 1
  fi
done < <(
  printf '%s' "$manifest_json" |
    jq -r '.hosts | to_entries[] | "\(.key)\t\(.value.defaultRice)\t\(.value.buildTarget)"'
)

while IFS=$'\t' read -r host rice target; do
  actual_host="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$target" '.[$target].host')"
  actual_rice="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$target" '.[$target].rice')"

  if [[ $actual_host != "$host" ]]; then
    echo "FAIL: target $target resolved host $actual_host, expected $host" >&2
    exit 1
  fi

  if [[ $actual_rice != "$rice" ]]; then
    echo "FAIL: target $target resolved rice $actual_rice, expected $rice" >&2
    exit 1
  fi
done < <(
  printf '%s' "$manifest_json" |
    jq -r '.hosts | to_entries[] | .key as $host | .value.targetsByRice | to_entries[] | "\($host)\t\(.key)\t\(.value)"'
)

echo "PASS: target manifest"
