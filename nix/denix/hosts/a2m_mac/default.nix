{ delib, pkgs, ... }:

let
  env = import ../../../env.nix;
in
delib.host {
  name = "a2m_mac";
  rice = "full"; # default rice; can switch to -minimum
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

    # Specify Nix CLI package for nix.conf generation
    nix.package = pkgs.nix;

    # Set primary user for homebrew
    system.primaryUser = user;

    users.users.${user} = {
      name = user;
      home = homeDir;
    };
  };
}

