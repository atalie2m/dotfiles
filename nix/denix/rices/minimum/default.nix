{ delib, ... }:
let
  modules = import ../../modules.nix { inherit delib; };
in
delib.rice {
  name = "minimum";

  home.imports = with delib.modules; [
    nixpkgsUnfree
    packages
    bash
    git
    gpg
    zsh
    starship
    terminal
    fonts
    smartBackup
    karabiner
  ];
}
