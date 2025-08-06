#!/bin/bash
# Git clean filter

# Load common system variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Replace all system information with their respective placeholders
<<<<<<< HEAD
perl -0 -pe "s|\"\Q$COMPUTER_NAME\E\"|\"u1’s MacBook Air\"|g; \
          s|\"\Q$SERIALIZED_COMPUTER_NAME\E\"|\"u1’s-MacBook-Air\"|g; \
          s|\"\Q$LOCAL_HOSTNAME\E\"|\"u1s-MacBookAir\"|g; \
          s|\"\Q$USER_NAME\E\"|\"u1\"|g; \
          s|\Q/Users/$USER_NAME\E|/Users/u1|g"
=======
perl -0 -pe "s|\"\Q$COMPUTER_NAME\E\"|\"u1’s MacBook Air\"|g; \
          s|\"\Q$SERIALIZED_COMPUTER_NAME\E\"|\"u1’s-MacBook-Air\"|g; \
          s|\"\Q$LOCAL_HOSTNAME\E\"|\"u1s-MacBookAir\"|g; \
          s|\"\Q$USER_NAME\E\"|\"u1\"|g; \
          s|\Q/Users/$USER_NAME\E|/Users/u1|g"
>>>>>>> parent of b86a51d (feat: implement CI setup script for Git filters and streamline filter application process)
