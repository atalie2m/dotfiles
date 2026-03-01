{ delib, lib, pkgs, ... }:

# Anthropic Claude Code
# Default: native app (Homebrew cask)
# Fallback: Nix overlay package (legacy npm-based path)

delib.module {
  name = "tools.aiCodingAgent.claudeCode";

  options = with delib; moduleOptions {
    enable = boolOption false;
    installMethod = enumOption [ "native" "overlay" ] "native";
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.claudeCode.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = { cfg, ... }: let
      useNative = cfg.installMethod == "native";
    in {
      tools.system.homebrewNative.enable = lib.mkDefault useNative;
      tools.system.homebrewNative.casks = lib.mkAfter (lib.optional useNative "claude-code");
      packages.claude-code-overlay.enable = lib.mkDefault (!useNative);
    };
  };

  home.ifEnabled = { cfg, ... }: let
    useNative = cfg.installMethod == "native";
  in {
    home.packages = lib.optionals (!useNative) [ pkgs.claude-code ];
  };
}
