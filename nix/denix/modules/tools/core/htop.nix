{ delib, lib, pkgs, ... }:

# tools.core.htop tool

delib.module {
  name = "tools.core.htop";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.htop.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.htop ];
  };
}
