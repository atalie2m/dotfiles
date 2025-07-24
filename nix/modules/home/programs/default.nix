{ config, pkgs, ... }:

{
  programs = {
    git = {
      enable = true;
    };

    gpg = {
      enable = true;
    };
  };
}
