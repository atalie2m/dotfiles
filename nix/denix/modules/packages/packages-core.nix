{ delib, pkgs, ... }:

# Core system packages and utilities
delib.module {
  name = "packages.core";

  options.packages.core = with delib.options; {
    enable = boolOption false;
    extraPackages = listOfOption package [];
  };

  home.ifEnabled = { cfg, myconfig, ... }: {
    home.packages = with pkgs; [
      # Shell utilities
      curl
      wget
      jq

      # File and text processing
      ripgrep
      fd
      bat
      eza

      # System tools
      htop
      tree
      unzip
      zip

      # Network tools
      nmap

    ] ++ cfg.extraPackages;
  };
}
