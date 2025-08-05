{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  darwin = { name, cfg, myconfig, ... }: {
    imports = [
      ../../../modules/homebrew/default.nix
    ];
  };

  home = { name, cfg, myconfig, ... }: {
    imports = [
      ../../../modules/home/shells/bash.nix
      ../../../modules/home/programs/git.nix
      ../../../modules/home/programs/gpg.nix
      ../../../modules/home/shells/zsh.nix
      ../../../modules/home/programs/starship.nix
      ../../../modules/home/karabiner.nix
    ];
  };
}
