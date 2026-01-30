{ delib, lib, pkgs, config, ... }:

# Zsh configuration

delib.module {
  name = "tools.shell.zsh";

  options = with delib; moduleOptions {
    enable = boolOption false;
    enableAutosuggestions = boolOption true;
    enableSyntaxHighlighting = boolOption true;
    enableCompletion = boolOption true;
    historySize = intOption 10000;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.shell.zsh.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    shellCfg = (myconfig.tools or {}).shell or {};

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

    commonShellInit = ''
      # Prefer GNU coreutils (unprefixed) when available
      if [ -d "${pkgs.coreutils}/libexec/gnubin" ]; then
        PATH="${pkgs.coreutils}/libexec/gnubin:$PATH"
        export PATH
      fi

      # Custom function for process search
      psgrep() {
        if [[ -z "''${1:-}" ]]; then
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
      if [[ $- == *i* ]] && [[ -n "''${IN_NIX_SHELL:-}" ]]; then
        echo "🚀 Nix develop environment active"
        if [[ -n "''${DEVENV_PROFILE:-}" ]]; then
          echo "Environment: ''${DEVENV_PROFILE}"
        elif [[ -n "''${NIX_SHELL_NAME:-}" ]]; then
          echo "Environment: ''${NIX_SHELL_NAME}"
        fi
      fi
    '';

    allAliases = commonAliases // shellCfg.extraAliases;
  in {
    programs.zsh = {
      enable = true;
      dotDir = ".nix";

      history = {
        size = cfg.historySize;
        save = cfg.historySize;
        ignoreDups = true;
        ignoreSpace = true;
      };

      shellAliases = allAliases // {
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

      autosuggestion.enable = cfg.enableAutosuggestions;
      syntaxHighlighting.enable = cfg.enableSyntaxHighlighting;
      inherit (cfg) enableCompletion;
    };

    home.sessionVariables = {
      ZDOTDIR = "$HOME/.nix";
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    programs.zsh.enable = lib.mkForce (
      (((myconfig.tools or {}).shell or {}).manageSystemShells or false) && cfg.enable
    );
  };
}
