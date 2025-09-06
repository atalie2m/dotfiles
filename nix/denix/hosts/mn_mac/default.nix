{ delib, pkgs, ... }:

let
  env = import ../../../env.nix;
in
delib.host {
  name = "mn_mac";
  rice = "mn"; # default rice; can switch to -minimum
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

    nix.package = pkgs.nix;

    # nix-darwin requires setting the primary user for user-scoped options (e.g., Homebrew)
    system.primaryUser = user;

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}
