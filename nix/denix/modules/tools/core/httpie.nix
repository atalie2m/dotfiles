{ delib, lib, pkgs, ... }:

# tools.core.httpie tool

delib.module {
  name = "tools.core.httpie";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.httpie.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.httpie ];
  };
}
