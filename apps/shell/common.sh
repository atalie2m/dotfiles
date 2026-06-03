# shellcheck shell=bash

dedupePath() {
  local dedupedPath

  dedupedPath="$(
    printf '%s' "$PATH" | awk -v RS=':' '
      BEGIN { ORS = ""; first = 1 }
      length($0) == 0 { next }
      !seen[$0]++ {
        if (!first) {
          printf ":"
        }
        printf "%s", $0
        first = 0
      }
    '
  )"

  export PATH="$dedupedPath"
}

dotfilesProfileDirs() {
  local profileDir
  local profileDirs="${DOTFILES_PROFILE_DIRS:-}"
  local profileUser="${USER:-${LOGNAME:-}}"

  while [[ $profileDirs == *:* ]]; do
    profileDir="${profileDirs%%:*}"
    if [[ -n $profileDir ]]; then
      printf '%s\n' "$profileDir"
    fi
    profileDirs="${profileDirs#*:}"
  done
  if [[ -n $profileDirs ]]; then
    printf '%s\n' "$profileDirs"
  fi

  if [[ -n $profileUser ]]; then
    printf '%s\n' "/etc/profiles/per-user/$profileUser"
  fi
  printf '%s\n' "$HOME/.nix-profile"
}

dotfilesAddProfileBins() {
  local binDir
  local pathPrefix=""
  local profileDir

  while IFS= read -r profileDir; do
    binDir="$profileDir/bin"
    if [[ -d $binDir ]]; then
      pathPrefix="${pathPrefix:+$pathPrefix:}$binDir"
    fi
  done < <(dotfilesProfileDirs)

  if [[ -n $pathPrefix ]]; then
    export PATH="$pathPrefix${PATH:+:}$PATH"
  fi
}

dotfilesSourceWithNounsetGuard() {
  local restore_nounset=0
  local source_path="$1"

  case $- in
    *u*) restore_nounset=1 ;;
  esac

  set +u
  # shellcheck disable=SC1090
  source "$source_path"
  if [[ $restore_nounset -eq 1 ]]; then
    set -u
  fi
}

dotfilesFirstProfileFile() {
  local profileDir
  local profileFile
  local relativePath="$1"

  while IFS= read -r profileDir; do
    profileFile="$profileDir/$relativePath"
    if [[ -f $profileFile ]]; then
      printf '%s\n' "$profileFile"
      return 0
    fi
  done < <(dotfilesProfileDirs)

  return 1
}

dotfilesIsMoshSession() {
  if [[ -n ${DOTFILES_MOSH_SESSION:-} ]]; then
    return 0
  fi

  local parentCommand=""
  local parentPid="${PPID:-}"

  if [[ -n $parentPid ]] && command -v ps >/dev/null 2>&1; then
    parentCommand="$(command ps -o comm= -p "$parentPid" 2>/dev/null || true)"
  fi

  case "$parentCommand" in
    *mosh-server*)
      export DOTFILES_MOSH_SESSION=1
      return 0
      ;;
  esac

  return 1
}

dotfilesSetControlCharEcho() {
  if ! command -v stty >/dev/null 2>&1; then
    return 0
  fi

  stty echoctl 2>/dev/null || stty ctlecho 2>/dev/null || true
}

dotfilesConfigureInteractiveTty() {
  if [[ $- != *i* ]] || [[ ! -t 0 ]]; then
    return 0
  fi

  dotfilesSetControlCharEcho
}

dotfilesAddProfileBins

dotfilesIsMoshSession || true
dotfilesConfigureInteractiveTty

hmSessionVars="$(dotfilesFirstProfileFile "etc/profile.d/hm-session-vars.sh" || true)"
if [[ -f $hmSessionVars ]]; then
  # Home Manager writes sessionPath/sessionVariables here; source it so
  # interactive shells pick up managed PATH entries like ~/.local/bin.
  # Clear the HM guard first because shells may inherit __HM_SESS_VARS_SOURCED
  # without inheriting the managed PATH entries we expect.
  unset __HM_SESS_VARS_SOURCED
  dotfilesSourceWithNounsetGuard "$hmSessionVars"
fi

if [[ $- == *i* ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

dedupePath

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

if [[ -f "$HOME/.ripgreprc" ]]; then
  export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
fi

commandNotFound="$(dotfilesFirstProfileFile "etc/profile.d/command-not-found.sh" || true)"
if [[ -f $commandNotFound ]]; then
  # shellcheck disable=SC1090
  source "$commandNotFound"
fi

export LESS='-R --mouse --wheel-lines=3'

if command -v bat >/dev/null 2>&1; then
  export LESSOPEN='|bat --paging=never --color=always %s'
  alias cat='bat --paging=never'
  alias less='bat --paging=always'
  alias f='fzf --preview "bat --color=always --style=numbers,changes {}"'
fi

if command -v batman >/dev/null 2>&1; then
  alias man='batman'
fi
if command -v batdiff >/dev/null 2>&1; then
  alias diff='batdiff'
fi
if command -v batgrep >/dev/null 2>&1; then
  alias grep='batgrep'
fi

if command -v tldr >/dev/null 2>&1; then
  alias tldru='tldr --update'
fi
if command -v chafa >/dev/null 2>&1; then
  alias img='chafa --fill=block --symbols=block'
fi
if command -v hexyl >/dev/null 2>&1; then
  alias hex='hexyl'
fi

if command -v rg >/dev/null 2>&1; then
  alias rg='rg --smart-case'
  alias rgi='rg -i'
  alias rgm='rg --files-with-matches'
fi
if command -v rga >/dev/null 2>&1; then
  alias rga='rga --smart-case'
fi
if command -v fd >/dev/null 2>&1; then
  alias fd='fd --hidden --follow --exclude .git'
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
if command -v fzf >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers,changes {}'"
fi

rgf() {
  command rg --smart-case --line-number --no-heading --color=always "$@" |
    fzf --ansi --delimiter ':' --preview 'bat --color=always --highlight-line {2} {1}'
}

if command -v nh >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    alias nos='nh darwin switch'
    alias nosb='nh darwin build'
    alias nosu='nh darwin switch --update'
  else
    alias nos='nh os switch'
    alias nosb='nh os build'
    alias nosu='nh os switch --update'
  fi
  alias noh='nh home switch'
fi
if command -v nom >/dev/null 2>&1; then
  alias nix-build='nom build'
fi

if command -v procs >/dev/null 2>&1; then
  alias ps='procs'
fi
if command -v curl >/dev/null 2>&1; then
  alias curlv='curl -v'
  alias curld='curl -O -L --progress-bar'
fi
curlj() {
  command curl -s "$@" | jq
}
if command -v wget >/dev/null 2>&1; then
  alias wget='wget --progress=bar:scroll'
fi
if command -v nmap >/dev/null 2>&1; then
  alias nmapq='nmap -sS -sV -T4'
  alias nmapf='nmap -sS -sV -sC -A -T4 -p-'
fi
if command -v xh >/dev/null 2>&1; then
  alias http='xh'
  alias https='xh --default-scheme=https'
fi
if command -v jq >/dev/null 2>&1; then
  alias jq='jq --color-output'
fi

if command -v docker >/dev/null 2>&1; then
  alias d='docker'
  alias dc='docker compose'
  alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
fi
if command -v podman >/dev/null 2>&1; then
  alias p='podman'
  alias pc='podman compose'
fi
if command -v kubectl >/dev/null 2>&1; then
  alias k='kubectl'
  alias kgp='kubectl get pods'
  alias kgs='kubectl get svc'
fi
if command -v kubecolor >/dev/null 2>&1; then
  alias kubectl='kubecolor'
  export KUBECOLOR_FORCE_COLORS=true
fi

dotfilesCpuCount() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    printf '1\n'
  fi
}

if command -v tar >/dev/null 2>&1; then
  alias tar='tar --zstd'
  alias compress='tar --zstd -cf'
  alias extract='tar --zstd -xf'
fi
if command -v pigz >/dev/null 2>&1; then
  alias pigz='pigz -p $(dotfilesCpuCount)'
fi

if command -v vivid >/dev/null 2>&1; then
  vividTheme="$(vivid generate catppuccin-mocha 2>/dev/null || vivid generate dracula 2>/dev/null || true)"
  if [[ -n ${vividTheme:-} ]]; then
    export LS_COLORS="$vividTheme"
  fi
  unset vividTheme
fi

if [[ -n ${DOTFILES_KEYCHAIN_KEYS:-} ]] && command -v keychain >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  eval "$(keychain --eval --agents ssh $DOTFILES_KEYCHAIN_KEYS)"
fi
