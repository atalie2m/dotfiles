{ delib, ... }:

delib.host {
  name = "common";
  rice = "full";
  type = "desktop";
  homeManagerSystem = "aarch64-darwin";

  home = { name, cfg, myconfig, ... }: {
    home.stateVersion = "25.05";
  };

  darwin = { name, cfg, myconfig, ... }: let
    user = myconfig.constants.username;
    homeDir = myconfig.constants.homeDirectory;
    platform = "${myconfig.constants.architecture}-darwin";
  in {
    system.stateVersion = 5;
    nixpkgs.hostPlatform = platform;

    # Set primary user for homebrew
    system.primaryUser = user;

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}
