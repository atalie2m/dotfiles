{ delib, lib, pkgs, ... }:

# tools.core.python3 tool

delib.module {
  name = "tools.core.python3";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.python3.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.python3 ];
  };
}
