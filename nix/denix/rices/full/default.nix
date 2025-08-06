{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  myconfig = {
    git.enable = true;
    gpg.enable = true;
    karabiner.enable = true;

    # Unified shell configuration
    shells = {
      enable = true;
      zsh.enable = true;
      bash.enable = true;
      starship.enable = true;
      defaultShell = "zsh";
    };

    # Native homebrew integration
    homebrew.native = {
      enable = true;

      # Keep existing brew-nix casks
      enableBrewNix = true;

      # Standard homebrew casks
#      casks = [
#        "google-chrome"
#        "visual-studio-code"
#        "docker"
#      ];

      # CLI tools via homebrew (if not available in nixpkgs)
 #     brews = [
 #       "mas"  # Mac App Store CLI
 #     ];

      # Mac App Store apps
#      masApps = {
#        "1Password 7 - Password Manager" = 1333542190;
#        "Xcode" = 497799835;
#      };
    };
  };
}
