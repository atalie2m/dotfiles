{ lib, writeShellApplication }:

writeShellApplication {
  name = "dotfiles-vscode-zsh";

  text = ''
    profile_dirs=()

    append_profile_dir() {
      local profile_dir="$1"
      if [[ -n "$profile_dir" ]]; then
        profile_dirs+=("$profile_dir")
      fi
    }

    split_profile_dirs() {
      local rest="$1"
      local part

      while [[ "$rest" == *:* ]]; do
        part="''${rest%%:*}"
        append_profile_dir "$part"
        rest="''${rest#*:}"
      done

      append_profile_dir "$rest"
    }

    prepend_path_dir() {
      local path_dir="$1"

      if [[ ! -d "$path_dir" ]]; then
        return 0
      fi

      case ":''${PATH:-}:" in
        *":$path_dir:"*) ;;
        *) PATH="$path_dir''${PATH:+:$PATH}" ;;
      esac
    }

    prepend_profile_bins() {
      local idx

      for ((idx = ''${#profile_dirs[@]} - 1; idx >= 0; idx--)); do
        prepend_path_dir "''${profile_dirs[$idx]}/bin"
      done

      export PATH
    }

    source_with_nounset_guard() {
      local restore_nounset=0
      local source_path="$1"

      case "$-" in
        *u*) restore_nounset=1 ;;
      esac

      set +u
      # shellcheck disable=SC1090
      source "$source_path"
      if [[ "$restore_nounset" -eq 1 ]]; then
        set -u
      fi
    }

    first_profile_file() {
      local relative_path="$1"
      local profile_dir

      for profile_dir in "''${profile_dirs[@]}"; do
        if [[ -f "$profile_dir/$relative_path" ]]; then
          printf '%s\n' "$profile_dir/$relative_path"
          return 0
        fi
      done

      return 1
    }

    choose_candidate() {
      local candidate="$1"

      if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi

      return 1
    }

    choose_zsh() {
      local candidate
      local candidates=()

      if [[ -n "''${DOTFILES_VSCODE_ZSH_BIN:-}" ]]; then
        if choose_candidate "$DOTFILES_VSCODE_ZSH_BIN"; then
          return 0
        fi

        printf 'dotfiles-vscode-zsh: DOTFILES_VSCODE_ZSH_BIN is not executable: %s\n' "$DOTFILES_VSCODE_ZSH_BIN" >&2
        return 127
      fi

      if [[ "$system_name" == "Darwin" && "$is_vscode_family" -eq 1 ]]; then
        choose_candidate "/bin/zsh" && return 0
      fi

      if [[ -n "$profile_user" ]]; then
        candidates+=("/etc/profiles/per-user/$profile_user/bin/zsh")
      fi

      if [[ -n "$home_dir" ]]; then
        candidates+=("$home_dir/.nix-profile/bin/zsh")
      fi

      candidate="$(command -v zsh 2>/dev/null || true)"
      candidates+=("$candidate" "/bin/zsh")

      for candidate in "''${candidates[@]}"; do
        choose_candidate "$candidate" && return 0
      done

      return 1
    }

    home_dir="''${HOME:-}"
    profile_user="''${USER:-''${LOGNAME:-}}"

    if [[ -n "''${DOTFILES_PROFILE_DIRS:-}" ]]; then
      split_profile_dirs "$DOTFILES_PROFILE_DIRS"
    fi

    if [[ -n "$profile_user" ]]; then
      append_profile_dir "/etc/profiles/per-user/$profile_user"
    fi

    if [[ -n "$home_dir" ]]; then
      append_profile_dir "$home_dir/.nix-profile"
    fi

    prepend_profile_bins

    if hm_session_vars="$(first_profile_file "etc/profile.d/hm-session-vars.sh")"; then
      unset __HM_SESS_VARS_SOURCED
      source_with_nounset_guard "$hm_session_vars"
      prepend_profile_bins
    fi

    home_nix_zshrc=""
    if [[ -n "$home_dir" ]]; then
      home_nix_zshrc="$home_dir/.nix/.zshrc"
    fi

    if [[ -n "''${DOTFILES_ZDOTDIR:-}" ]]; then
      export ZDOTDIR="$DOTFILES_ZDOTDIR"
    elif [[ -n "''${VSCODE_INJECTION:-}" ]]; then
      if [[ -z "''${USER_ZDOTDIR:-}" && -n "$home_nix_zshrc" && -f "$home_nix_zshrc" ]]; then
        export USER_ZDOTDIR="$home_dir/.nix"
      fi
    elif [[ -n "$home_nix_zshrc" && -f "$home_nix_zshrc" ]]; then
      if [[ -z "''${ZDOTDIR:-}" || ! -f "''${ZDOTDIR:-}/.zshrc" ]]; then
        export ZDOTDIR="$home_dir/.nix"
      fi
    fi

    system_name="$(uname -s 2>/dev/null || true)"
    is_vscode_family=0
    case "''${TERM_PROGRAM:-}" in
      vscode | cursor | kiro) is_vscode_family=1 ;;
    esac
    if [[ -n "''${VSCODE_INJECTION:-}" || -n "''${VSCODE_SHELL_INTEGRATION:-}" || -n "''${VSCODE_NONCE:-}" ]]; then
      is_vscode_family=1
    fi

    if ! zsh_bin="$(choose_zsh)"; then
      printf 'dotfiles-vscode-zsh: no executable zsh found\n' >&2
      exit 127
    fi

    exec "$zsh_bin" "$@"
  '';

  meta = {
    description = "dotfiles-owned VS Code zsh launcher with stable Home Manager environment setup";
    platforms = lib.platforms.unix;
    mainProgram = "dotfiles-vscode-zsh";
  };
}
