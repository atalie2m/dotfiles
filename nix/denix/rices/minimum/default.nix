{ delib, ... }:

delib.rice {
  name = "minimum";

  myconfig = {
    nixpkgs.unfree.enable = true;
    terminal.enable = true;
    fonts.enable = true;
    packages.enable = true;
    smartBackup.enable = true;
    git.enable = true;
  };
}
