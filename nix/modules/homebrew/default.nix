{ config, pkgs, ... }:

{
  # Enable brew-nix
  brew-nix.enable = true;

  # Install applications via brew-nix
  environment.systemPackages = [
    pkgs.brewCasks.latest
    pkgs.brewCasks.rio
    pkgs.brewCasks.keyclu
  ];
}
