{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    git
    gnupg
    curl
    wget
    pinentry_mac
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
