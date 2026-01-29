{ delib, lib, pkgs, config, ... }:

# OpenAI Codex CLI

delib.module {
  name = "tools.aiCodingAgent.codex";

  options.tools.aiCodingAgent.codex = with delib.options; {
    enable = boolOption false;
  };

  # Default tool enablement to the group toggle unless explicitly overridden.
  myconfig = {
    always = { parent, ... }: {
      tools.aiCodingAgent.codex.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = {
      packages.codex-overlay.enable = lib.mkDefault true;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.codex ];
  };
}
