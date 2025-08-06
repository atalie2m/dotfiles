{ delib, lib, pkgs, ... }:

# Unified shell configuration for zsh, bash, and starship
delib.module {
  name = "shells";

  options.shells = with delib.options; {
    enable = boolOption false;

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
      # Custom function for process search
      psgrep() {
        ps aux | grep -i "$1" | grep -v grep
      }

      # Show nix develop environment info
      if [[ -n "$IN_NIX_SHELL" ]]; then
        echo "🚀 Nix develop environment active"
        if [[ -n "$name" ]]; then
          echo "Environment: $name"
        fi
      fi
    '';

    allAliases = commonAliases // cfg.extraAliases;
  in {
    # Zsh configuration
    programs.zsh = lib.mkIf cfg.zsh.enable {
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

        # Load local ~/.zshrc if it exists
        if [[ -f ~/.zshrc ]]; then
          source ~/.zshrc
        fi
      '';

      autosuggestion.enable = cfg.zsh.enableAutosuggestions;
      syntaxHighlighting.enable = cfg.zsh.enableSyntaxHighlighting;
      enableCompletion = cfg.zsh.enableCompletion;
    };

    # Bash configuration
    programs.bash = lib.mkIf cfg.bash.enable {
      enable = true;
      enableCompletion = cfg.bash.enableCompletion;

      # Source Nix-managed bashrc located under ~/.nix
      initExtra = ''
        if [[ -f "$HOME/.nix/.bashrc" ]]; then
          source "$HOME/.nix/.bashrc"
        fi
      '';
    };

    # Nix-managed bash configuration stored in ~/.nix/.bashrc
    home.file.".nix/.bashrc" = lib.mkIf cfg.bash.enable {
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

    # Wrapper ~/.bashrc to load the Nix-managed configuration and optional local overrides
    home.file.".bashrc" = lib.mkIf cfg.bash.enable {
      text = ''
        # Source Nix-managed bash configuration
        if [ -f "$HOME/.nix/.bashrc" ]; then
          source "$HOME/.nix/.bashrc"
        fi

        # Source user overrides
        if [ -f "$HOME/.bashrc.local" ]; then
          source "$HOME/.bashrc.local"
        fi
      '';
    };

    # Starship prompt configuration - use custom starship.toml file
    programs.starship = lib.mkIf cfg.starship.enable {
      enable = true;
      enableZshIntegration = cfg.zsh.enable;
      # Bash integration handled manually in ~/.nix/.bashrc
      enableBashIntegration = false;
    };

    # Link the custom starship configuration file
    xdg.configFile."starship.toml" = lib.mkIf cfg.starship.enable {
      source = ../../../../apps/starship.toml;
    };

    # Session variables
    home.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.zsh.enable {
        ZDOTDIR = "$HOME/.nix";
      })
      # Let Home Manager handle SHELL variable automatically based on enabled shells
    ];
  };

  # Darwin-specific shell configuration
  darwin.ifEnabled = { cfg, ... }: {
    programs.zsh.enable = cfg.zsh.enable;
    programs.bash.enable = cfg.bash.enable;
  };
}
