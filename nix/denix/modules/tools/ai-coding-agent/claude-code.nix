{ delib, lib, pkgs, config, ... }:

# Anthropic Claude Code CLI

delib.module {
  name = "tools.aiCodingAgent.claudeCode";

  options.tools.aiCodingAgent.claudeCode = with delib.options; {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.claudeCode.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      packages.claude-code-overlay.enable = lib.mkDefault true;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.claude-code ];
  };
}
