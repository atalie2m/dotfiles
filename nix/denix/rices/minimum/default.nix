{ delib, ... }:

delib.rice {
  name = "minimum";

  home = { name, cfg, myconfig, ... }: {
    programs.gpg.enable = true;
    programs.git.enable = true;
  };
}
