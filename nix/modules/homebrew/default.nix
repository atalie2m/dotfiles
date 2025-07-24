{ config, pkgs, ... }:

{
  # Enable brew-nix
  brew-nix.enable = true;

  # Install applications using brew-nix
  environment.systemPackages = with pkgs; [
    brewCasks.rio
    brewCasks.keyclu
  ];
}
