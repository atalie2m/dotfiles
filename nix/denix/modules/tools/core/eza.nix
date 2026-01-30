{ delib, lib, pkgs, ... }:

# tools.core.eza tool

delib.module {
  name = "tools.core.eza";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.eza.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.eza ];
  };
}
