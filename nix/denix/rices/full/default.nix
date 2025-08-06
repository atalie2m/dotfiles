{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  myconfig = {
    homebrew.enable = true;
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
  };
}
