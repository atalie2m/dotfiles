{ delib, lib, pkgs, ... }:

# tools.core.unzip tool

delib.module {
  name = "tools.core.unzip";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.unzip.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.unzip ];
  };
}
