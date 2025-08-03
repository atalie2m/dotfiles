{ pkgs, ... }:

let
  common = import ./common.nix { inherit pkgs; };
in
{
  programs.zsh = {
    enable = true;
    dotDir = ".nix";

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
    };

    inherit (common) shellAliases;

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

  home.sessionVariables = {
    ZDOTDIR = "$HOME/.nix";
    SHELL = "${pkgs.zsh}/bin/zsh";
  };
}
