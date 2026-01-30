{ delib, lib, ... }:

# AeroSpace window manager (Homebrew cask)
delib.module {
  name = "tools.system.aerospace";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.system.aerospace.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = { ... }: {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.taps = lib.mkAfter [
        "nikitabobko/tap"
      ];
      tools.system.homebrewNative.casks = lib.mkAfter [
        "nikitabobko/tap/aerospace"
      ];
    };
  };

  darwin.ifEnabled = { ... }: { };
}
