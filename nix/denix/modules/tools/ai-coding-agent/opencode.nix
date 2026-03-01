{ delib, lib, ... }:

# OpenCode CLI (Homebrew tap formula)
# Official tap is recommended by upstream for the most up-to-date releases.

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.aiCodingAgent.opencode";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.aiCodingAgent.opencode.enable";
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.taps = lib.mkAfter [ "anomalyco/tap" ];
      tools.system.homebrewNative.brews = lib.mkAfter [ "anomalyco/tap/opencode" ];
    };
  };

  darwin.ifEnabled = { ... }: { };
}
