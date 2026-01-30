{ delib, lib, pkgs, ... }:

# tools.dev.terraform tool

delib.module {
  name = "tools.dev.terraform";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.terraform.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.terraform ];
  };
}
