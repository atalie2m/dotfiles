{ inputs, lib, ... }:

let
  # Import centralized environment configuration
  env = import ../env.nix;
  configurations = env.hosts;

  # Create Home Manager configurations for all hosts
  mkHomeConfigurations = lib.mapAttrs (hostName: hostConfig:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import ../modules/nixpkgs { inherit inputs; inherit (hostConfig) system; };
      modules = [
        ../modules/home/home-manager.nix
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
