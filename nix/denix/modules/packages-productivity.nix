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
      starship  # shell prompt
      
      # AI and productivity tools (if available in nixpkgs)
      
    ] ++ (lib.optionals cfg.includeAITools [
      # AI tools (if available)
      # codex  # might not be in nixpkgs
      # gemini-cli  # might not be in nixpkgs
      
    ]) ++ cfg.extraPackages;
  };
}