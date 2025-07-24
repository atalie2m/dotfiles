{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
  };

  programs.gpg = {
    enable = true;
  };
}
