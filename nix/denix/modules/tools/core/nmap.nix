{ delib, lib, pkgs, ... }:

# tools.core.nmap tool

delib.module {
  name = "tools.core.nmap";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.nmap.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.nmap ];
  };
}
