# Centralized nixpkgs configuration that extracts settings from separate files
{ inputs, system }:

let
  lib = inputs.nixpkgs.lib;
  
  # Evaluate the unfree module to extract the config
  unfreeModule = import ./unfree.nix { inherit lib; };
  unfreeConfig = unfreeModule.nixpkgs.config;
  
  # Evaluate the overlays module to extract the overlays
  overlaysModule = import ./overlays.nix { inherit lib; };
  overlaysList = overlaysModule.nixpkgs.overlays;
in
import inputs.nixpkgs {
  inherit system;
  config = unfreeConfig;
  overlays = overlaysList;
}