_: {
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
    initExtra = ''
      # Load local ~/.zshrc
      # This might break the benefits of Nix, but I rather fancy it.
      if [[ -f ~/.zshrc ]]; then
        source ~/.zshrc
      fi

      # search for processes by name
      psgrep() {
        ps aux | grep -i "$1" | grep -v grep
      }
    '';

    # auto-completion and syntax highlighting
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
  };

  home.sessionVariables = {
    ZDOTDIR = "$HOME/.nix";
  };
}
