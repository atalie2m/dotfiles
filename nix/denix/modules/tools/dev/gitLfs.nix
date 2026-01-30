{ delib, lib, pkgs, ... }:

# tools.dev.gitLfs tool

delib.module {
  name = "tools.dev.gitLfs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.dev.gitLfs.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs."git-lfs" ];
  };
}
