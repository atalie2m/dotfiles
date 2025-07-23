#!/bin/bash
# Git smudge filter

# Load common hostname variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Use perl for safer regex replacement
perl -pe "s/\Q\"{{COMPUTER_NAME}}\"\E/\"$COMPUTER_NAME\"/g; s/\Q\"{{SERIALIZED_COMPUTER_NAME}}\"\E/\"$SERIALIZED_COMPUTER_NAME\"/g; s/\Q\"{{LOCAL_HOSTNAME}}\"\E/\"$LOCAL_HOSTNAME\"/g"
