{ delib, lib, ... }:

# GitHub Copilot CLI (Homebrew cask)

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.aiCodingAgent.githubCopilotCli";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.aiCodingAgent.githubCopilotCli.enable";
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.casks = lib.mkAfter [ "copilot-cli" ];
    };
  };

  darwin.ifEnabled = { ... }: { };
}
