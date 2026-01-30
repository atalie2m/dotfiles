{ delib, lib, pkgs, ... }:

# tools.core.ripgrep tool

delib.module {
  name = "tools.core.ripgrep";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.ripgrep.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.ripgrep ];
  };
}
