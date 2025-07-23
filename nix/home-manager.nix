{ config, pkgs, ... }:

{
  home.username = "{{USER_NAME}}";
  home.homeDirectory = "/Users/{{USER_NAME}}";

  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
