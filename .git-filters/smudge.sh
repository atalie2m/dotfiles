#!/bin/bash
# Git smudge filter

# Load common system variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Replace placeholders with actual system information
perl -0 -pe "s|\"\Q{{COMPUTER_NAME}}\E\"|\"$COMPUTER_NAME\"|g; \
          s|\"\Q{{SERIALIZED_COMPUTER_NAME}}\E\"|\"$SERIALIZED_COMPUTER_NAME\"|g; \
          s|\"\Q{{LOCAL_HOSTNAME}}\E\"|\"$LOCAL_HOSTNAME\"|g; \
          s|\"\Q{{USER_NAME}}\E\"|\"$USER_NAME\"|g; \
          s|\Q/Users/{{USER_NAME}}\E|/Users/$USER_NAME|g"
