#!/bin/bash
# Git smudge filter

# Load common system variables
source "$(dirname "$0")/common.sh"

# Replace placeholders with actual system information
perl -pe "s/\Q\"{{COMPUTER_NAME}}\"\E/\"$COMPUTER_NAME\"/g; \
          s/\Q\"{{SERIALIZED_COMPUTER_NAME}}\"\E/\"$SERIALIZED_COMPUTER_NAME\"/g; \
          s/\Q\"{{LOCAL_HOSTNAME}}\"\E/\"$LOCAL_HOSTNAME\"/g; \
          s/\Q\"{{USER_NAME}}\"\E/\"$USER_NAME\"/g"
