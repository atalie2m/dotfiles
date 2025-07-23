{ config, pkgs, ... }:

{
  home = {
    username = "{{USER_NAME}}";
    homeDirectory = "/Users/{{USER_NAME}}";
    stateVersion = "25.05";
  };

  programs.home-manager.enable = true;
}
