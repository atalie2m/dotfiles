{ delib, lib, pkgs, ... }:

# tools.core.bat tool

delib.module {
  name = "tools.core.bat";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.bat.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.bat ];
  };
}
