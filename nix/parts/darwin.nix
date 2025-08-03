# Darwin system configuration generation
{ inputs, lib, self, ... }:

let
  # Import centralized environment configuration
  env = import ../env.nix;
  configurations = env.hosts;

  # Profile-specific modules
  profileDarwinModules = {
    standard = ../profiles/standard/darwin/standard.nix;
    commercial = ../profiles/commercial/darwin/commercial.nix;
  };

  profileHomeModules = {
    commercial = ../profiles/commercial/home/commercial.nix;
  };

  # Create Darwin configurations for all hosts
  mkDarwinConfigurations = lib.mapAttrs (hostName: hostConfig:
    let
      profile = hostConfig.profile or "standard";
      profileModule = profileDarwinModules.${profile} or null;
      profileHomeModule = profileHomeModules.${profile} or null;
    in
    inputs.nix-darwin.lib.darwinSystem {
      inherit (hostConfig) system;
      modules =
        [
          inputs.brew-nix.darwinModules.default
          inputs.home-manager.darwinModules.home-manager
          ../modules/darwin
          ../modules/homebrew
          ../modules/nixpkgs/unfree.nix
          ../modules/nixpkgs/overlays.nix
          ../hosts/darwin.nix        # Base Darwin settings
        ]
        ++ lib.optional (profileModule != null) profileModule
        ++ [
          { networking.hostName = hostName; }
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${hostConfig.username} = {
                imports =
                  [ ../modules/home/home-manager.nix ]
                  ++ lib.optional (profileHomeModule != null) profileHomeModule;
                home = {
                  inherit (hostConfig) username;
                  homeDirectory = "/Users/${hostConfig.username}";
                };
              };
            };
          }
        ];
      specialArgs = {
        inherit self hostName;
        inherit (inputs) brew-nix;
        inherit (hostConfig) username;
      };
    }
  ) configurations;
in
{
  flake.darwinConfigurations = mkDarwinConfigurations;
}
