{ delib, ... }:

let
  env = import ../../../env.nix;
in
delib.host {
  name = "commercial";
  rice = "minimum";
  type = "desktop";
  homeManagerSystem = env.platform;

  home = { name, cfg, myconfig, ... }: {
    home.stateVersion = env.stateVersion.home;
  };

  darwin = { name, cfg, myconfig, ... }: let
    user = env.username;
    homeDir = env.homeDirectory;
    platform = env.platform;
  in {
    system.stateVersion = env.stateVersion.darwin;
    nixpkgs.hostPlatform = platform;

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}
