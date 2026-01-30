{ delib, lib, pkgs, ... }:

# tools.core.coreutils tool

delib.module {
  name = "tools.core.coreutils";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.coreutils.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.coreutils ];
  };
}
