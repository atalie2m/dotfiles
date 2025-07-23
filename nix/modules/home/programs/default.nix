{ config, pkgs, ... }:

{
  imports = [
    ./git.nix
    ./gpg.nix
  ];
}
