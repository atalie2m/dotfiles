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
      ../../../modules/home/services/smart-backup.nix
    ];
  };
}
