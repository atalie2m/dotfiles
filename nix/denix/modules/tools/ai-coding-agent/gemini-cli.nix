{ delib, lib, ... }:

# Google Gemini CLI
# Native only (Homebrew formula)

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.aiCodingAgent.geminiCli";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = mkEnableDefault "tools.aiCodingAgent.geminiCli.enable";
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.brews = lib.mkAfter [ "gemini-cli" ];
    };
  };
}
