{ config, pkgs, ... }:

{
  imports = [
    ./programs
  ];

  home = {
    stateVersion = "25.05";
  };

  programs.home-manager.enable = true;
}
