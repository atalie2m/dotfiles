{ config, pkgs, inputs, ... }:

{
  nixpkgs.overlays = [ inputs.brew-nix.overlays.default ];

  brew-nix.enable = true;

  environment.systemPackages = with pkgs; [
    brewCasks.rio
    brewCasks.keyclu
    brewCasks.latest
  ];
}
