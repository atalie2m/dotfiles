#!/usr/bin/env bash
# Configure git filters to handle system-specific information
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Ensure a clean working tree before rewriting files
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Please commit or stash changes before running setup." >&2
    exit 1
fi

# Register clean and smudge filters
git config filter.system-info.clean "$SCRIPT_DIR/clean.sh"
git config filter.system-info.smudge "$SCRIPT_DIR/smudge.sh"
git config filter.system-info.required true

# Re-checkout tracked files to apply smudge filter
git reset --hard

# Populate env.nix with host-specific values
rm -f "nix/env.nix"
git checkout -- nix/env.nix

echo "Git filter 'system-info' configured and env.nix populated."
