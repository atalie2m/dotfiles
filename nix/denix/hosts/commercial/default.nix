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
    home = {
      inherit (env) username homeDirectory;
      stateVersion = env.stateVersion.home;
    };
  };

  darwin = { name, cfg, myconfig, ... }: let
    inherit (env) username homeDirectory platform;
    user = username;
    homeDir = homeDirectory;
  in {
    system.stateVersion = env.stateVersion.darwin;
    nixpkgs.hostPlatform = platform;

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}
