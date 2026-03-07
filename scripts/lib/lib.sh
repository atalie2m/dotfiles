#!/usr/bin/env bash

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for lib_file in core.sh inputs.sh repo.sh targets.sh text.sh; do
  # shellcheck disable=SC1090
  source "$LIB_DIR/$lib_file"
done
