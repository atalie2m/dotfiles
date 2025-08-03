_: {
  programs.zsh = {
    enable = true;
    dotDir = ".nix";
  };

  home.sessionVariables = {
    ZDOTDIR = "$HOME/.nix";
  };
}