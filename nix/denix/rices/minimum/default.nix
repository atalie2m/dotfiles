{ delib, ... }:

delib.rice {
  name = "minimum";

  home = { name, cfg, myconfig, ... }: {
    imports = [ 
      ../../../modules/nixpkgs/unfree.nix
      ../../../modules/home/packages.nix
      ../../../modules/home/shells/bash.nix
      ../../../modules/home/programs/git.nix
      ../../../modules/home/programs/gpg.nix
      ../../../modules/home/shells/zsh.nix
      ../../../modules/home/programs/starship.nix
      ../../../modules/home/programs/terminals.nix
      ../../../modules/home/fonts.nix
      ../../../modules/home/services/smart-backup.nix
      ../../../modules/home/karabiner.nix
    ];
  };
}
