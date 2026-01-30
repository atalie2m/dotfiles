{ delib, lib, pkgs, ... }:

# tools.dev.gh tool

delib.module {
  name = "tools.dev.gh";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.gh.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.gh ];
  };
}
