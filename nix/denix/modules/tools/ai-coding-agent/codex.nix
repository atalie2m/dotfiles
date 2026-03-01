{ delib, lib, ... }:

# OpenAI Codex CLI
# Native only (Homebrew cask)

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.aiCodingAgent.codex";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = mkEnableDefault "tools.aiCodingAgent.codex.enable";
    ifEnabled = {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.casks = lib.mkAfter [ "codex" ];
    };
  };
}
