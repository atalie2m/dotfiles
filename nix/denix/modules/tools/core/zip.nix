{ delib, lib, pkgs, ... }:

# tools.core.zip tool

delib.module {
  name = "tools.core.zip";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.zip.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.zip ];
  };
}
