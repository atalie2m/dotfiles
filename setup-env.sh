#!/usr/bin/env bash
# Wrapper to configure Git filters and populate env.nix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/.git-filters/setup.sh" "$@"
