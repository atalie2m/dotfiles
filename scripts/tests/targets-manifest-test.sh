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
                profile = targets.${target}.config.myconfig.profile.name;
              };
            })
            (builtins.attrNames targets))
    '
)"

if ! printf '%s' "$manifest_json" | jq -e '.hosts | type == "object" and length > 0' >/dev/null; then
  echo "FAIL: target manifest is empty or malformed" >&2
  exit 1
fi

if ! printf '%s' "$manifest_json" | jq -e '.hosts | to_entries | all(.[]; (.value.supportedProfiles | sort) == (.value.targetsByProfile | keys | sort))' >/dev/null; then
  echo "FAIL: supportedProfiles does not match targetsByProfile keys" >&2
  exit 1
fi

if ! printf '%s' "$manifest_json" | jq -e '.hosts | to_entries | all(.[]; .value.targetsByProfile[.value.defaultProfile] == .value.buildTarget)' >/dev/null; then
  echo "FAIL: targetsByProfile.defaultProfile must equal buildTarget for every host" >&2
  exit 1
fi

if ! jq -n --argjson manifest "$manifest_json" --argjson metadata "$target_metadata_json" -e '
  def manifestTargets:
    ([ $manifest.hosts
      | to_entries[]
      | .value
      | [ .buildTarget, (.targetsByProfile | to_entries[] | .value) ]
    ] | flatten | unique | sort);
  def actualTargets:
    ($metadata | keys | sort);
  manifestTargets == actualTargets
' >/dev/null; then
  echo "FAIL: manifest target set does not exactly match darwinConfigurations attrNames" >&2
  exit 1
fi

while IFS=$'\t' read -r host default_profile build_target; do
  if ! grep -Fq "\`${host}\` (default profile: \`${default_profile}\`)" docs/commands.md; then
    echo "FAIL: docs/commands.md is missing host/default-profile pair for $host" >&2
    exit 1
  fi

  actual_host="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$build_target" '.[$target].host')"
  actual_profile="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$build_target" '.[$target].profile')"

  if [[ $actual_host != "$host" ]]; then
    echo "FAIL: buildTarget $build_target resolved host $actual_host, expected $host" >&2
    exit 1
  fi

  if [[ $actual_profile != "$default_profile" ]]; then
    echo "FAIL: buildTarget $build_target resolved profile $actual_profile, expected $default_profile" >&2
    exit 1
  fi
done < <(
  printf '%s' "$manifest_json" |
    jq -r '.hosts | to_entries[] | "\(.key)\t\(.value.defaultProfile)\t\(.value.buildTarget)"'
)

while IFS=$'\t' read -r host profile target; do
  actual_host="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$target" '.[$target].host')"
  actual_profile="$(printf '%s' "$target_metadata_json" | jq -r --arg target "$target" '.[$target].profile')"

  if [[ $actual_host != "$host" ]]; then
    echo "FAIL: target $target resolved host $actual_host, expected $host" >&2
    exit 1
  fi

  if [[ $actual_profile != "$profile" ]]; then
    echo "FAIL: target $target resolved profile $actual_profile, expected $profile" >&2
    exit 1
  fi
done < <(
  printf '%s' "$manifest_json" |
    jq -r '.hosts | to_entries[] | .key as $host | .value.targetsByProfile | to_entries[] | "\($host)\t\(.key)\t\(.value)"'
)

echo "PASS: target manifest"
