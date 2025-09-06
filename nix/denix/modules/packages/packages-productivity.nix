{ delib, lib, pkgs, ... }:

# Productivity and AI tools
delib.module {
  name = "packages.productivity";

  options.packages.productivity = with delib.options; {
    enable = boolOption false;
    includeAITools = boolOption true;
    extraPackages = listOfOption package [];
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    aiEnabled = cfg.includeAITools && (myconfig.codingAgents.claudeCode || myconfig.codingAgents.codex);
  in {
    home.packages = with pkgs; [
      # Terminal enhancements
      starship


    ] ++ (lib.optionals aiEnabled [
      codex
      gemini-cli
      claude-code

    ]) ++ cfg.extraPackages;
  };
}
