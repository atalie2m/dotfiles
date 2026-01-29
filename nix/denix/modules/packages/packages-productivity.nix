{ delib, pkgs, ... }:

# Productivity tools
delib.module {
  name = "packages.productivity";

  options.packages.productivity = with delib.options; {
    enable = boolOption false;
    extraPackages = listOfOption package [];
  };

  home.ifEnabled = { cfg, ... }: {
    home.packages = with pkgs; [
      # Terminal enhancements
      starship
    ] ++ cfg.extraPackages;
  };
}
