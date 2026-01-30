{ delib, lib, pkgs, ... }:

# tools.dev.go tool

delib.module {
  name = "tools.dev.go";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.go.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.go ];
  };
}
