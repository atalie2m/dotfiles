# shellcheck shell=bash

psgrep() {
  if [[ -z ${1:-} ]]; then
    echo "Usage: psgrep <pattern>" >&2
    return 1
  fi

  if command -v rg >/dev/null 2>&1; then
    ps aux | rg -i -- "$1"
  else
    # shellcheck disable=SC2009
    ps aux | grep -i -- "$1" | grep -v "[g]rep"
  fi
}

if [[ $- == *i* ]]; then
  if command -v gpgconf >/dev/null 2>&1; then
    gpgAgentSshSocket="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)"
    if [[ -n ${gpgAgentSshSocket:-} ]] && [[ -S ${gpgAgentSshSocket} ]]; then
      useGpgAgent=0

      if [[ -z ${SSH_AUTH_SOCK:-} ]] || [[ ! -S ${SSH_AUTH_SOCK} ]]; then
        useGpgAgent=1
      else
        currentAgentHasIdentity=0
        gpgAgentHasIdentity=0

        if ssh-add -l >/dev/null 2>&1; then
          currentAgentHasIdentity=1
        fi
        if SSH_AUTH_SOCK="${gpgAgentSshSocket}" ssh-add -l >/dev/null 2>&1; then
          gpgAgentHasIdentity=1
        fi

        if [[ ${currentAgentHasIdentity} -eq 0 ]] && [[ ${gpgAgentHasIdentity} -eq 1 ]]; then
          useGpgAgent=1
        fi
      fi

      if [[ ${useGpgAgent} -eq 1 ]]; then
        export SSH_AUTH_SOCK="${gpgAgentSshSocket}"
      fi
    fi
  fi

  gpgTty="$(tty 2>/dev/null || true)"
  if [[ -n ${gpgTty:-} ]] && [[ ${gpgTty} != "not a tty" ]]; then
    export GPG_TTY="${gpgTty}"
  fi
fi
