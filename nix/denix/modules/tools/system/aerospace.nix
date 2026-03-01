{ delib, lib, ... }:

# AeroSpace window manager (Homebrew cask)

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.system.aerospace";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.system.aerospace.enable";
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
