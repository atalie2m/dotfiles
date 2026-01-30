{ delib, lib, pkgs, ... }:

# tools.core.yq tool

delib.module {
  name = "tools.core.yq";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.yq.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.yq ];
  };
}
