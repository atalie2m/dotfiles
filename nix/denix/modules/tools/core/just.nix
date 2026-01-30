{ delib, lib, pkgs, ... }:

# tools.core.just tool

delib.module {
  name = "tools.core.just";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.just.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.just ];
  };
}
