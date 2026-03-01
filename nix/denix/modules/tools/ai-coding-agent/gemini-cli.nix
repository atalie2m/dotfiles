{ delib, lib, ... }:

# Google Gemini CLI
# Native only (Homebrew formula)

delib.module {
  name = "tools.aiCodingAgent.geminiCli";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.geminiCli.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.brews = lib.mkAfter [ "gemini-cli" ];
    };
  };
}
