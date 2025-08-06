{ delib, lib, pkgs, ... }:

# Productivity and AI tools
delib.module {
  name = "packages.productivity";

  options.packages.productivity = with delib.options; {
    enable = boolOption false;
    includeAITools = boolOption true;
    extraPackages = listOfOption package [];
  };

  home.ifEnabled = { cfg, myconfig, ... }: {
    home.packages = with pkgs; [
      # Terminal enhancements
      starship


    ] ++ (lib.optionals cfg.includeAITools [
      codex-cli
      gemini-cli
      claude-code

    ]) ++ cfg.extraPackages;
  };
}
