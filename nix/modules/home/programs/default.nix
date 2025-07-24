{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    git
    gnupg
    curl
    wget
  ];

  programs = {
    git = {
      enable = true;
    };

    gpg = {
      enable = true;
    };
  };
}
