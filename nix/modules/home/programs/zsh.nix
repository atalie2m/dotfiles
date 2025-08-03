{ pkgs, ... }: {
  programs.zsh = {
    enable = true;
    dotDir = ".nix";

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
    };

    shellAliases = {
      # file and directory operations
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";
    };

    # Custom functions
    initContent = ''
      # Load local ~/.zshrc
      # This might break the benefits of Nix, but I rather fancy it.
      if [[ -f ~/.zshrc ]]; then
        source ~/.zshrc
      fi

      # Ensure starship is initialized in nix develop environments
      if command -v starship >/dev/null 2>&1; then
        eval "$(starship init zsh)"
      fi

      # search for processes by name
      psgrep() {
        ps aux | grep -i "$1" | grep -v grep
      }
    '';

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
  };

  # Ensure starship is initialized for zsh
  programs.starship.enableZshIntegration = true;

  # Configure bash for nix develop environments
  programs.bash = {
    enable = true;
    shellAliases = {
      # file and directory operations
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";

      # development aliases
      dev = "nix develop";
      build = "nix build";
      run = "nix run";
      search = "nix search";

      # git shortcuts
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline";
    };

    initExtra = ''
      # Only load bash customizations in nix develop environments
      if [[ -n "$IN_NIX_SHELL" ]]; then
        # Initialize starship for bash in nix develop
        if command -v starship >/dev/null 2>&1; then
          eval "$(starship init bash)"
        fi

        # Custom function for process search
        psgrep() {
          ps aux | grep -i "$1" | grep -v grep
        }

        # Show current nix develop environment
        echo "🚀 Nix develop environment active"
        if [[ -n "$name" ]]; then
          echo "Environment: $name"
        fi
      fi
    '';
  };

  home.sessionVariables = {
    ZDOTDIR = "$HOME/.nix";
    SHELL = "${pkgs.zsh}/bin/zsh";
  };
}
