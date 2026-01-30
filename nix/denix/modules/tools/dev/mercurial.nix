{ delib, lib, pkgs, ... }:

# tools.dev.mercurial tool

delib.module {
  name = "tools.dev.mercurial";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.mercurial.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.mercurial ];
  };
}
