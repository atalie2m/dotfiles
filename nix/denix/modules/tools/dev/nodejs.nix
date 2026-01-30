{ delib, lib, pkgs, ... }:

# tools.dev.nodejs tool

delib.module {
  name = "tools.dev.nodejs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.nodejs.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.nodejs ];
  };
}
