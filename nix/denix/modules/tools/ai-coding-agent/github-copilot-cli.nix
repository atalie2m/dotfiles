{ delib, lib, ... }:

# GitHub Copilot CLI (Homebrew cask)

delib.module {
  name = "tools.aiCodingAgent.githubCopilotCli";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.githubCopilotCli.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.casks = lib.mkAfter [ "copilot-cli" ];
    };
  };

  darwin.ifEnabled = { ... }: { };
}
