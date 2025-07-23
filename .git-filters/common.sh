#!/bin/bash
# Common variables for Git filters

# Get raw hostname values from macOS
COMPUTER_NAME=$(scutil --get ComputerName)
LOCAL_HOSTNAME=$(scutil --get LocalHostName)

# Generate serialized version (spaces to hyphens, keep apostrophes)
SERIALIZED_COMPUTER_NAME=$(echo "$COMPUTER_NAME" | tr ' ' '-')

# Export variables for use in other scripts
export COMPUTER_NAME
export SERIALIZED_COMPUTER_NAME
export LOCAL_HOSTNAME
