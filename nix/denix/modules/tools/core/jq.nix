{ delib, lib, pkgs, ... }:

# tools.core.jq tool

delib.module {
  name = "tools.core.jq";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.jq.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.jq ];
  };
}
