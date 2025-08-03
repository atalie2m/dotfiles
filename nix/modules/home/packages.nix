{ pkgs, ... }:
let
  packages = import ../../packages/standard.nix { inherit pkgs; };
in {
  home.packages = packages;
}
