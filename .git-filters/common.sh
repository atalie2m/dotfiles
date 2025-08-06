#!/bin/bash
# Common variables and functions for Git filters

# Get script directory (can be used by sourcing scripts)
if [[ -z "$SCRIPT_DIR" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Get some values from the system
if command -v scutil >/dev/null 2>&1; then
    COMPUTER_NAME=$(scutil --get ComputerName)
    LOCAL_HOSTNAME=$(scutil --get LocalHostName)
else
    COMPUTER_NAME=$(hostname)
    LOCAL_HOSTNAME=$(hostname -s)
fi
USER_NAME=$(whoami)

# Generate serialized version (spaces to hyphens, keep apostrophes)
SERIALIZED_COMPUTER_NAME=$(echo "$COMPUTER_NAME" | tr ' ' '-')

# Export variables for use in other scripts
export COMPUTER_NAME
export SERIALIZED_COMPUTER_NAME
export LOCAL_HOSTNAME
export USER_NAME
export SCRIPT_DIR
