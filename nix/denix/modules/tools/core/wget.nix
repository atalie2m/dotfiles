{ delib, lib, pkgs, ... }:

# tools.core.wget tool

delib.module {
  name = "tools.core.wget";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.wget.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.wget ];
  };
}
