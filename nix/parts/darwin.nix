# Darwin system configurations
{ inputs, lib, self, ... }:

let
  # Import centralized environment configuration
  env = import ../env.nix;
  configurations = env.hosts;

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
        ../hosts/darwin
        ../hosts/darwin/standard
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
      };
    }
  ) configurations;
in
{
  flake.darwinConfigurations = mkDarwinConfigurations;
}