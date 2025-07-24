{ config, pkgs, brew-nix, ... }:

{
  nixpkgs.overlays = [ brew-nix.overlays.default ];

  brew-nix = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [
    brewCasks.rio
    brewCasks.keyclu
  ];
}
