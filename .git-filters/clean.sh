#!/bin/bash
# Git clean filter

# Load common system variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Replace all system information with their respective placeholders
perl -0 -pe "s|\"\Q$COMPUTER_NAME\E\"|\"{{COMPUTER_NAME}}\"|g; \
          s|\"\Q$SERIALIZED_COMPUTER_NAME\E\"|\"{{SERIALIZED_COMPUTER_NAME}}\"|g; \
          s|\"\Q$LOCAL_HOSTNAME\E\"|\"{{LOCAL_HOSTNAME}}\"|g; \
          s|\"\Q$USER_NAME\E\"|\"{{USER_NAME}}\"|g; \
          s|\Q/Users/$USER_NAME\E|/Users/u1|g"
