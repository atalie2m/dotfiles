{ delib, ... }:

delib.host {
  name = "commercial";
  rice = "minimum";
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

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}
