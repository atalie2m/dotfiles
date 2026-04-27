#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MATRIX_SCRIPT="$ROOT/scripts/matrix-tools.sh"

if [[ ! -f $MATRIX_SCRIPT ]]; then
  echo "test: matrix-tools script not found: $MATRIX_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/matrix-tools-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/nix" <<'EOF_FAKE_NIX'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_NIX_LOG_FILE:?}"
printf '%s\n' "$*" >>"$log_file"

if [[ "$*" == *"--apply x: builtins.concatStringsSep"* ]]; then
  printf 'own_mac\nwork_mac\n'
  exit 0
fi

if [[ "$*" == *"matrix-tools.nix"*".text targets"* && "$*" == *"full = false"* ]]; then
  printf 'target\tcore.enable\tdev.enable\nown_mac\ttrue\ttrue\nwork_mac\ttrue\ttrue\n'
  exit 0
fi

if [[ "$*" == *"matrix-tools.nix"*".json targets"* && "$*" == *"full = true"* ]]; then
  printf '{"mode":"full","columns":["core.enable","dev.enable","dev.git.enable"],"rows":[{"target":"own_mac","values":{"core.enable":true,"dev.enable":true,"dev.git.enable":true}}]}'
  exit 0
fi

echo "fake nix: unexpected invocation: $*" >&2
exit 1
EOF_FAKE_NIX
chmod +x "$fake_bin/nix"

export HOME="$tmp_root/home"
mkdir -p "$HOME"
export PATH="$fake_bin:$PATH"
export FACTS="path:$tmp_root/facts"
export FACTS_DIR="$tmp_root/facts"
export SECRETS="path:$tmp_root/secrets"
export SECRETS_DIR="$tmp_root/secrets"
mkdir -p "$FACTS_DIR" "$SECRETS_DIR"
export FAKE_NIX_LOG_FILE="$tmp_root/nix.log"

text_out="$tmp_root/text.out"
json_out="$tmp_root/json.out"

bash "$MATRIX_SCRIPT" >"$text_out"

if ! grep -Fq $'target\tcore.enable\tdev.enable' "$text_out"; then
  echo "FAIL: default matrix output header mismatch" >&2
  cat "$text_out" >&2 || true
  exit 1
fi

if ! grep -Fq $'work_mac\ttrue\ttrue' "$text_out"; then
  echo "FAIL: default matrix output row mismatch" >&2
  cat "$text_out" >&2 || true
  exit 1
fi

bash "$MATRIX_SCRIPT" --full --format json >"$json_out"

if ! grep -Fq '"mode":"full"' "$json_out"; then
  echo "FAIL: full json matrix mode missing" >&2
  cat "$json_out" >&2 || true
  exit 1
fi

if ! grep -Fq '"dev.git.enable":true' "$json_out"; then
  echo "FAIL: full json matrix expected toggle missing" >&2
  cat "$json_out" >&2 || true
  exit 1
fi

if ! grep -Fq 'full = true' "$FAKE_NIX_LOG_FILE"; then
  echo "FAIL: matrix-tools did not request full=true expression" >&2
  cat "$FAKE_NIX_LOG_FILE" >&2 || true
  exit 1
fi

echo "PASS: matrix tools smoke"
