{ delib, ... }:

delib.rice {
  name = "minimum";

  myconfig = {
    nixpkgs.unfree.enable = true;
    terminal.enable = true;
    fonts.enable = true;
  };

  home = { name, cfg, myconfig, ... }: {
    imports = [
      ../../../modules/home/packages.nix
      ../../../modules/home/shells/bash.nix
      ../../../modules/home/programs/git.nix
      ../../../modules/home/programs/gpg.nix
      ../../../modules/home/shells/zsh.nix
      ../../../modules/home/programs/starship.nix
      ../../../modules/home/services/smart-backup.nix
      ../../../modules/home/karabiner.nix
    ];
  };
}
