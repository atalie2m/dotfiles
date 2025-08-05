{ delib, ... }:

delib.rice {
  name = "minimum";

  home = { name, cfg, myconfig, ... }: {
    imports = [ 
      ../../../modules/home/programs/gpg.nix
      ../../../modules/home/programs/git.nix
    ];
  };
}
