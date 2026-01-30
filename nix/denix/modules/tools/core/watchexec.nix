{ delib, lib, pkgs, ... }:

# tools.core.watchexec tool

delib.module {
  name = "tools.core.watchexec";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.core.watchexec.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.watchexec ];
  };
}
