{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  myconfig = {
    homebrew.enable = true;
    bash.enable = true;
    git.enable = true;
    gpg.enable = true;
    zsh.enable = true;
    starship.enable = true;
    karabiner.enable = true;
  };
}
