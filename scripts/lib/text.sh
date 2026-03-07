#!/usr/bin/env bash

resolve_text_tool_bin() {
  local tool_name="$1"
  local tool_path=""
  local fallback_path=""

  tool_path="$(command -v "$tool_name" 2>/dev/null || true)"
  if [[ -n $tool_path ]]; then
    printf '%s\n' "$tool_path"
    return 0
  fi

  for fallback_path in "/usr/bin/$tool_name" "/bin/$tool_name"; do
    if [[ -x $fallback_path ]]; then
      printf '%s\n' "$fallback_path"
      return 0
    fi
  done

  die "required command not found in PATH: $tool_name"
}

DOTFILES_TEXT_AWK_BIN="${DOTFILES_TEXT_AWK_BIN:-$(resolve_text_tool_bin awk)}"
DOTFILES_TEXT_DIFF_BIN="${DOTFILES_TEXT_DIFF_BIN:-$(resolve_text_tool_bin diff)}"
DOTFILES_TEXT_GREP_BIN="${DOTFILES_TEXT_GREP_BIN:-$(resolve_text_tool_bin grep)}"

canonicalize_text_to_file() {
  local source_file="$1"
  local output_file="$2"

  [[ -f $source_file ]] || return 1
  "$DOTFILES_TEXT_AWK_BIN" '{ sub(/\r$/, ""); print }' "$source_file" >"$output_file"
}

append_canonicalized_text_to_file() {
  local source_file="$1"
  local output_file="$2"

  [[ -f $source_file ]] || return 1
  "$DOTFILES_TEXT_AWK_BIN" '{ sub(/\r$/, ""); print }' "$source_file" >>"$output_file"
}

extract_managed_block() {
  local source_file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local output_file="$4"

  [[ -f $source_file ]] || return 2

  if "$DOTFILES_TEXT_AWK_BIN" -v begin="$begin_marker" -v end="$end_marker" '
    BEGIN {
      beginCount = 0
      endCount = 0
      inBlock = 0
    }
    $0 == begin {
      beginCount++
      if (beginCount > 1 || inBlock == 1) {
        exit 3
      }
      inBlock = 1
      next
    }
    $0 == end {
      endCount++
      if (inBlock == 0 || endCount > 1) {
        exit 3
      }
      inBlock = 0
      next
    }
    inBlock == 1 {
      print
    }
    END {
      if (beginCount == 0 && endCount == 0) {
        exit 2
      }
      if (beginCount == 1 && endCount == 1 && inBlock == 0) {
        exit 0
      }
      exit 3
    }
  ' "$source_file" >"$output_file"; then
    return 0
  else
    case "$?" in
    2) return 2 ;;
    3) return 3 ;;
    *) return 3 ;;
    esac
  fi
}

replace_managed_block_in_file() {
  local source_file="$1"
  local desired_file="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local output_file="$5"

  "$DOTFILES_TEXT_AWK_BIN" -v begin="$begin_marker" -v end="$end_marker" -v desired="$desired_file" '
    BEGIN {
      beginCount = 0
      endCount = 0
      inBlock = 0
    }
    $0 == begin {
      beginCount++
      if (beginCount > 1 || inBlock == 1) {
        exit 3
      }
      print $0
      while ((getline line < desired) > 0) {
        sub(/\r$/, "", line)
        print line
      }
      close(desired)
      inBlock = 1
      next
    }
    $0 == end {
      endCount++
      if (inBlock == 0 || endCount > 1) {
        exit 3
      }
      inBlock = 0
      print $0
      next
    }
    inBlock == 0 {
      print
    }
    END {
      if (beginCount == 0 && endCount == 0) {
        exit 2
      }
      if (beginCount == 1 && endCount == 1 && inBlock == 0) {
        exit 0
      }
      exit 3
    }
  ' "$source_file" >"$output_file"
}

print_unified_diff() {
  local left_file="$1"
  local right_file="$2"

  "$DOTFILES_TEXT_DIFF_BIN" -u "$left_file" "$right_file" || true
}

text_file_contains_exact_line() {
  local expected_line="$1"
  local source_file="$2"

  "$DOTFILES_TEXT_GREP_BIN" -Fqx "$expected_line" "$source_file"
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}
