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

    # Use common shell aliases with zsh-specific additions
    shellAliases = common.shellAliases // {
      # Zsh-specific hidden command
      helloworld = "echo '👋 Hello from Zsh! You are running in a Zsh shell.'";
    };

    # Custom functions
    initContent = ''
      # Load local ~/.zshrc
      # This might break the benefits of Nix, but I rather fancy it.
      if [[ -f ~/.zshrc ]]; then
        source ~/.zshrc
      fi

      # Load common shell initialization
      ${common.commonShellInit}
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
