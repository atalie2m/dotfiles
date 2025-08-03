{ inputs, lib, ... }:

let
  # Import centralized environment configuration
  env = import ../env.nix;
  configurations = env.hosts;

  # Profile-specific home modules
  profileHomeModules = {
    commercial = ../profiles/commercial/home/commercial.nix;
  };

  # Create Home Manager configurations for all hosts
  mkHomeConfigurations = lib.mapAttrs (hostName: hostConfig:
    let
      profile = hostConfig.profile or "standard";
      profileHomeModule = profileHomeModules.${profile} or null;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import ../modules/nixpkgs { inherit inputs; inherit (hostConfig) system; };
      modules =
        [ ../modules/home/home-manager.nix ]
        ++ lib.optional (profileHomeModule != null) profileHomeModule
        ++ [
          {
            home = {
              inherit (hostConfig) username;
              homeDirectory = "/Users/${hostConfig.username}";
            };
          }
        ];
    }
  ) configurations;
in
{
  flake.homeConfigurations = mkHomeConfigurations;
}
