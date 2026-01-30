{ delib, lib, pkgs, ... }:

# tools.core.tree tool

delib.module {
  name = "tools.core.tree";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.tree.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.tree ];
  };
}
