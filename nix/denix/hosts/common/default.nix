{ delib, ... }:

let
  env = import ../../../env.nix;
in
delib.host {
  name = "common";
  rice = "full";
  type = "desktop";
  homeManagerSystem = env.platform;

  home = { name, cfg, myconfig, ... }: {
    home.stateVersion = env.stateVersion.home;
  };

  darwin = { name, cfg, myconfig, ... }: let
    inherit (env) username homeDirectory platform;
    user = username;
    homeDir = homeDirectory;
  in {
    system.stateVersion = env.stateVersion.darwin;
    nixpkgs.hostPlatform = platform;

    # Set primary user for homebrew
    system.primaryUser = user;

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}
