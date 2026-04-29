#!/usr/bin/env bash
set -euo pipefail

emacs_app="${EMACS_PLUS_APP:-/Applications/Emacs.app}"
plist="$emacs_app/Contents/Info.plist"
plistbuddy="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"
codesign_bin="${CODESIGN:-/usr/bin/codesign}"
skip_codesign="${EMACS_PLUS_SKIP_CODESIGN:-0}"

find_brew_prefix() {
  if [[ -n ${HOMEBREW_PREFIX:-} && -x ${HOMEBREW_PREFIX:-}/bin/brew ]]; then
    printf '%s\n' "$HOMEBREW_PREFIX"
    return 0
  fi

  local candidate
  for candidate in /opt/homebrew /usr/local; do
    if [[ -x $candidate/bin/brew ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

find_gcc_bin() {
  local brew_prefix="$1"
  local candidate
  local candidate_major
  local gcc_bin=""
  local gcc_major=""

  shopt -s nullglob
  for candidate in "$brew_prefix"/bin/gcc-[0-9]*; do
    [[ -x $candidate ]] || continue
    candidate_major="${candidate##*-}"
    [[ $candidate_major =~ ^[0-9]+$ ]] || continue
    if [[ -z $gcc_major || $candidate_major -gt $gcc_major ]]; then
      gcc_bin="$candidate"
      gcc_major="$candidate_major"
    fi
  done
  shopt -u nullglob

  [[ -n $gcc_bin ]] && printf '%s\n' "$gcc_bin"
}

find_emutls_dir() {
  local brew_prefix="$1"
  local gcc_bin="$2"
  local gcc_major="$3"
  local gcc_machine
  local emutls_dir
  local emutls_file

  gcc_machine="$("$gcc_bin" -dumpmachine 2>/dev/null || true)"
  if [[ -n $gcc_machine ]]; then
    for emutls_dir in \
      "$brew_prefix/opt/gcc/lib/gcc/current/gcc/$gcc_machine/$gcc_major" \
      "$brew_prefix/lib/gcc/current/gcc/$gcc_machine/$gcc_major"; do
      if [[ -f $emutls_dir/libemutls_w.a ]]; then
        printf '%s\n' "$emutls_dir"
        return 0
      fi
    done
  fi

  emutls_file="$("$gcc_bin" -print-file-name=libemutls_w.a 2>/dev/null || true)"
  if [[ -f $emutls_file ]]; then
    dirname "$emutls_file"
  fi
}

plist_key_exists() {
  local key="$1"
  "$plistbuddy" -c "Print :LSEnvironment:$key" "$plist" >/dev/null 2>&1
}

plist_get() {
  local key="$1"
  "$plistbuddy" -c "Print :LSEnvironment:$key" "$plist" 2>/dev/null || true
}

plist_set_string() {
  local key="$1"
  local value="$2"

  if [[ $(plist_get "$key") == "$value" ]]; then
    return 1
  fi

  if plist_key_exists "$key"; then
    "$plistbuddy" -c "Set :LSEnvironment:$key $value" "$plist"
  else
    "$plistbuddy" -c "Add :LSEnvironment:$key string $value" "$plist"
  fi
}

if [[ ! -f $plist || ! -x $plistbuddy ]]; then
  exit 0
fi

brew_prefix="$(find_brew_prefix || true)"
[[ -n $brew_prefix ]] || exit 0

gcc_bin="$(find_gcc_bin "$brew_prefix" || true)"
[[ -n $gcc_bin ]] || exit 0

gcc_major="${gcc_bin##*-}"
emutls_dir="$(find_emutls_dir "$brew_prefix" "$gcc_bin" "$gcc_major" || true)"
[[ -n $emutls_dir ]] || exit 0

desired_cc="$brew_prefix/opt/gcc/bin/gcc-$gcc_major"
if [[ ! -x $desired_cc ]]; then
  desired_cc="$brew_prefix/bin/gcc-$gcc_major"
fi
desired_library_path="$emutls_dir:$brew_prefix/lib/gcc/current:$brew_prefix/lib"
changed=0

if ! "$plistbuddy" -c "Print :LSEnvironment" "$plist" >/dev/null 2>&1; then
  "$plistbuddy" -c "Add :LSEnvironment dict" "$plist"
  changed=1
fi

if plist_set_string CC "$desired_cc"; then
  changed=1
fi

if plist_set_string LIBRARY_PATH "$desired_library_path"; then
  changed=1
fi

if [[ $changed -eq 1 ]]; then
  touch "$emacs_app"
  if [[ $skip_codesign != 1 && -x $codesign_bin ]]; then
    "$codesign_bin" --force --deep --sign - "$emacs_app" >/dev/null
  fi
fi
