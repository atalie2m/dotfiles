#!/bin/bash
# Git clean filter

# Load common system variables
source "$(dirname "$0")/common.sh"

# Replace all system information with their respective placeholders
perl -pe "s/\Q\"$COMPUTER_NAME\"\E/\"{{COMPUTER_NAME}}\"/g; \
          s/\Q\"$SERIALIZED_COMPUTER_NAME\"\E/\"{{SERIALIZED_COMPUTER_NAME}}\"/g; \
          s/\Q\"$LOCAL_HOSTNAME\"\E/\"{{LOCAL_HOSTNAME}}\"/g; \
          s/\Q\"$USER_NAME\"\E/\"{{USER_NAME}}\"/g; \
          s|\Q/Users/$USER_NAME\E|/Users/{{USER_NAME}}|g"
