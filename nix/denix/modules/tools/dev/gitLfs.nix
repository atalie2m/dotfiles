{ delib, lib, ... }:

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

}
