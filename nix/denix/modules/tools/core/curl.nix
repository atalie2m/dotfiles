{ delib, lib, pkgs, ... }:

# tools.core.curl tool

delib.module {
  name = "tools.core.curl";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.curl.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.curl ];
  };
}
