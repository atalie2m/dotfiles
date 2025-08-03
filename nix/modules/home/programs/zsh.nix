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

      # nix develop with zsh
      nix-dev = "nix develop --command zsh";
      nd = "nix develop --command zsh";
    };

    # Custom functions
    initContent = ''
      # Load local ~/.zshrc
      # This might break the benefits of Nix, but I rather fancy it.
      if [[ -f ~/.zshrc ]]; then
        source ~/.zshrc
      fi

      # search for processes by name
      psgrep() {
        ps aux | grep -i "$1" | grep -v grep
      }

      # nix develop with zsh - works with any project's flake.nix
      ndev() {
        if [[ $# -eq 0 ]]; then
          nix develop --command zsh
        else
          nix develop "$@" --command zsh
        fi
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
