#!/bin/bash
# Git clean filter: Replace system-specific values with placeholders
# This script is run when files are staged (git add)

set -euo pipefail

# Source common variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Read input from stdin
input=$(cat)

# Replace actual values with placeholders
output="$input"
output=$(echo "$output" | sed "s|$COMPUTER_NAME|{{COMPUTER_NAME}}|g")
output=$(echo "$output" | sed "s|$SERIALIZED_COMPUTER_NAME|{{SERIALIZED_COMPUTER_NAME}}|g")
output=$(echo "$output" | sed "s|$LOCAL_HOSTNAME|{{LOCAL_HOSTNAME}}|g")
output=$(echo "$output" | sed "s|$USER_NAME|{{USER_NAME}}|g")

# Output the cleaned content
echo "$output"
