{ delib, lib, pkgs, ... }:

# Unified shell configuration for zsh, bash, and starship
delib.module {
  name = "shells";

  options.shells = with delib.options; {
    enable = boolOption false;
    manageSystemShells = boolOption false;

    zsh = {
      enable = boolOption false;
      enableAutosuggestions = boolOption true;
      enableSyntaxHighlighting = boolOption true;
      enableCompletion = boolOption true;
      historySize = intOption 10000;
    };

    bash = {
      enable = boolOption false;
      enableCompletion = boolOption true;
      historySize = intOption 10000;
    };

    starship = {
      enable = boolOption false;
    };

    defaultShell = strOption "zsh";
    extraAliases = attrsOption {};
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    # Common shell aliases
    commonAliases = {
      # File and directory operations
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";

      # Development aliases
      dev = "nix develop";
      build = "nix build";
      run = "nix run";
      search = "nix search";

      # Git shortcuts
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline";
    };

    # Common shell initialization
    commonShellInit = ''
      # Prefer GNU coreutils (unprefixed) when available
      if [ -d "${pkgs.coreutils}/libexec/gnubin" ]; then
        PATH="${pkgs.coreutils}/libexec/gnubin:$PATH"
        export PATH
      fi

      # Custom function for process search
      psgrep() {
        if [[ -z "${1:-}" ]]; then
          echo "Usage: psgrep <pattern>" >&2
          return 1
        fi
        if command -v rg >/dev/null 2>&1; then
          ps aux | rg -i -- "$1"
        else
          ps aux | grep -i -- "$1" | grep -v "[g]rep"
        fi
      }

      # Show nix develop environment info (interactive shells only)
      if [[ $- == *i* ]] && [[ -n "${IN_NIX_SHELL:-}" ]]; then
        echo "🚀 Nix develop environment active"
        if [[ -n "${DEVENV_PROFILE:-}" ]]; then
          echo "Environment: ${DEVENV_PROFILE}"
        elif [[ -n "${NIX_SHELL_NAME:-}" ]]; then
          echo "Environment: ${NIX_SHELL_NAME}"
        fi
      fi
    '';

    allAliases = commonAliases // cfg.extraAliases;
  in {
    # Program configurations
    programs = {
      # Zsh configuration
      zsh = lib.mkIf cfg.zsh.enable {
        enable = true;
        dotDir = ".nix";

        history = {
          size = cfg.zsh.historySize;
          save = cfg.zsh.historySize;
          ignoreDups = true;
          ignoreSpace = true;
        };

        shellAliases = allAliases // {
          # Zsh-specific alias
          helloworld = "echo '👋 Hello from Zsh! You are running in a Zsh shell.'";
        };

        initContent = ''
          ${commonShellInit}

          # Avoid right-prompt artifacts on resize and when typing
          # - transient_rprompt hides RPROMPT while typing
          # - prompt_cr/prompt_sp improve redraw on wraps and partial lines
          setopt TRANSIENT_RPROMPT
          setopt PROMPT_CR
          setopt PROMPT_SP
          # keep a small gap from terminal edge to avoid wrap glitches
          ZLE_RPROMPT_INDENT=1
          # clear end-of-line mark to prevent leftovers on reflow
          PROMPT_EOL_MARK=""
          # full refresh on terminal resize
          TRAPWINCH() { zle && zle -R }

          # Load local ~/.zshrc if it exists
          if [[ -f ~/.zshrc ]]; then
            source ~/.zshrc
          fi
          
        '';

        autosuggestion.enable = cfg.zsh.enableAutosuggestions;
        syntaxHighlighting.enable = cfg.zsh.enableSyntaxHighlighting;
        inherit (cfg.zsh) enableCompletion;
      };

      # Bash configuration
      bash = lib.mkIf cfg.bash.enable {
        enable = true;
        inherit (cfg.bash) enableCompletion;

        # Source Nix-managed bashrc located under ~/.nix
        initExtra = ''
          if [[ -f "$HOME/.nix/.bashrc" ]]; then
            source "$HOME/.nix/.bashrc"
          fi
        '';
      };

      # Starship prompt configuration - use custom starship.toml file
      starship = lib.mkIf cfg.starship.enable {
        enable = true;
        enableZshIntegration = cfg.zsh.enable;
        # Bash integration handled manually in ~/.nix/.bashrc
        enableBashIntegration = false;
      };
    };

    # Home configuration
    home = {
      # File configurations
      file = {
        # Nix-managed bash configuration stored in ~/.nix/.bashrc
        ".nix/.bashrc" = lib.mkIf cfg.bash.enable {
          text = ''
            # History configuration
            HISTCONTROL=ignoredups:ignorespace
            HISTSIZE=${toString cfg.bash.historySize}
            HISTFILESIZE=$(( ${toString cfg.bash.historySize} * 2 ))

            # Common shell initialization
            ${commonShellInit}

            # Shell aliases (shared and Bash specific)
            ${lib.concatStringsSep "" (lib.mapAttrsToList (name: value: ''alias ${name}="${value}"\n'') allAliases)}
            alias helloworld="echo '👋 Hello from Bash! You are running in a Bash shell.'"

            # Initialize Starship prompt if available
            if command -v starship >/dev/null 2>&1; then
              eval "$(starship init bash)"
            fi

            # Load user-specific Bash customizations if present
            if [[ -f "$HOME/.bashrc.local" ]]; then
              source "$HOME/.bashrc.local"
            fi
          '';
        };

      };

      # Session variables
      sessionVariables = lib.mkMerge [
        (lib.mkIf cfg.zsh.enable {
          ZDOTDIR = "$HOME/.nix";
        })
        # Let Home Manager handle SHELL variable automatically based on enabled shells
      ];
    };

    # XDG configuration
    xdg.configFile."starship.toml" = lib.mkIf cfg.starship.enable {
      source = ../../../../apps/starship.toml;
    };
  };

  # Darwin-specific shell configuration
  darwin.ifEnabled = { cfg, ... }: {
    programs.zsh.enable = lib.mkForce (cfg.manageSystemShells && cfg.zsh.enable);
    programs.bash.enable = lib.mkForce (cfg.manageSystemShells && cfg.bash.enable);
  };
}
