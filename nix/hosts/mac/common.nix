# Common modules and configuration for nix-darwin
{ pkgs, lib, config, ... }:
let
  flake = builtins.getFlake (toString ./.);
in
{
  nix.settings.experimental-features = "nix-command flakes";

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
  system.stateVersion = 6;

  nixpkgs.hostPlatform = "aarch64-darwin";
}
