{ delib, lib, pkgs, config, ... }:

# Google Gemini CLI

delib.module {
  name = "tools.aiCodingAgent.geminiCli";

  options.tools.aiCodingAgent.geminiCli = with delib.options; {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.geminiCli.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      packages.gemini-cli-overlay.enable = lib.mkDefault true;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.gemini-cli ];
  };
}
