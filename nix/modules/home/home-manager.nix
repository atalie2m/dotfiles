{ config, pkgs, ... }:

let
  env = import ../../env.nix;
in
{
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/gpg.nix
  ];

  home = {
    stateVersion = env.defaults.stateVersion.home;
  };

  programs.home-manager.enable = true;
}
