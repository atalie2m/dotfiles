{ delib, lib, pkgs, ... }:

# tools.dev.awscli2 tool

delib.module {
  name = "tools.dev.awscli2";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.awscli2.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.awscli2 ];
  };
}
