{ delib, lib, ... }:

# OpenAI Codex CLI
# Native only (Homebrew cask)

delib.module {
  name = "tools.aiCodingAgent.codex";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.codex.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.casks = lib.mkAfter [ "codex" ];
    };
  };
}
