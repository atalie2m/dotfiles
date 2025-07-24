{ config, pkgs, ... }:

{
  brew-nix.enable = true;

  # Import cask applications and add them to system packagesSS
  environment.systemPackages = import ./brew-nix/cask-apps.nix { inherit pkgs; };
}
