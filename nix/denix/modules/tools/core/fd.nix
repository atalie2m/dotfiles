{ delib, lib, pkgs, ... }:

# tools.core.fd tool

delib.module {
  name = "tools.core.fd";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.fd.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.fd ];
  };
}
