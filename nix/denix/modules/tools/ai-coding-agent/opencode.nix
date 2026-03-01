{ delib, lib, ... }:

# OpenCode CLI (Homebrew tap formula)
# Official tap is recommended by upstream for the most up-to-date releases.

delib.module {
  name = "tools.aiCodingAgent.opencode";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.opencode.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.taps = lib.mkAfter [ "anomalyco/tap" ];
      tools.system.homebrewNative.brews = lib.mkAfter [ "anomalyco/tap/opencode" ];
    };
  };

  darwin.ifEnabled = { ... }: { };
}
