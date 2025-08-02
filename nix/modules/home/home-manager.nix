{ config, pkgs, ... }:

let
  env = import ../../env.nix;
in
{
  imports = [
    ./programs
  ];

  home = {
    stateVersion = env.defaults.stateVersion.home;
  };

  programs.home-manager.enable = true;
}
