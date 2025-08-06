#!/usr/bin/env bash
# Configure git filters to handle system-specific information - CI version
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Git Filter Setup (CI Mode) ==="

# Make filter scripts executable
chmod +x "$SCRIPT_DIR"/*.sh
echo "✅ Made filter scripts executable"

# Check permissions
ls -la "$SCRIPT_DIR"/*.sh

# Register clean and smudge filters
git config filter.system-info.clean "$SCRIPT_DIR/clean.sh"
git config filter.system-info.smudge "$SCRIPT_DIR/smudge.sh"
git config filter.system-info.required true
echo "✅ Configured git filters"

# Test the smudge filter using bash explicitly
echo "🧪 Testing smudge filter:"
echo 'username = "u1";' | bash "$SCRIPT_DIR/smudge.sh"

# Apply smudge filter directly to all files that need it
echo "🔄 Applying filters to files with placeholders..."

# Process each file that contains placeholders
git ls-files | while read -r file; do
    if [[ -f "$file" ]] && grep -q "{{.*}}" "$file" 2>/dev/null; then
        echo "  Processing: $file"
        bash "$SCRIPT_DIR/smudge.sh" < "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    fi
done

echo "✅ Filter application completed"

# Verify key files were processed
if [[ -f "nix/env.nix" ]]; then
    echo "📋 Verification - env.nix username line:"
    grep "username" nix/env.nix | head -1 || echo "❌ No username line found"
fi

echo "✅ Git filter 'system-info' configured for CI."
