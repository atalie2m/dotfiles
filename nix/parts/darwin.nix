# Darwin system configuration generation
{ inputs, lib, self, ... }:

let
  # Import centralized environment configuration
  env = import ../env.nix;
  configurations = env.hosts;

  # Profile modules will be imported within the modules list to get access to specialArgs

  # Create Darwin configurations for all hosts
  mkDarwinConfigurations = lib.mapAttrs (hostName: hostConfig:
    inputs.nix-darwin.lib.darwinSystem {
      inherit (hostConfig) system;
      modules = [
        inputs.brew-nix.darwinModules.default
        inputs.home-manager.darwinModules.home-manager
        ../modules/darwin
        ../modules/homebrew
        ../modules/nixpkgs/unfree.nix
        ../modules/nixpkgs/overlays.nix
        ../hosts/darwin.nix        # Base Darwin settings
        ../profiles/${hostConfig.profile}/darwin/${hostConfig.profile}.nix
        { networking.hostName = hostName; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${hostConfig.username} = {
              imports = [ ../modules/home/home-manager.nix ];
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
        delib = inputs.denix.lib;
      };
    }
  ) configurations;
in
{
  flake.darwinConfigurations = mkDarwinConfigurations;
}
