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
      coreutils
      curl
      wget
      jq
      yq
      httpie

      # File and text processing
      ripgrep
      fd
      bat
      eza
      watchexec

      # System tools
      htop
      tree
      unzip
      zip
      just

      # Programming languages
      python3

      # Network tools
      nmap

    ] ++ cfg.extraPackages;
  };
}
