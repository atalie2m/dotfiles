{ inputs, config, self, lib, ... }:

let
  # Use a configuration-based approach with multiple possible hostnames
  configurations = {
    "{{LOCAL_HOSTNAME}}" = {
      system = "aarch64-darwin";
      username = "{{USER_NAME}}";
    };
  };

  # Create configurations for all possible hosts
  mkDarwinConfigurations = lib.mapAttrs (hostName: hostConfig:
    inputs.nix-darwin.lib.darwinSystem {
      system = hostConfig.system;
      modules = [
        inputs.brew-nix.darwinModules.default
        inputs.home-manager.darwinModules.home-manager
        ../modules/darwin
        ../hosts/darwin/mac
        { networking.hostName = hostName; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${hostConfig.username} = import ../modules/home/home-manager.nix;
          };
        }
      ];
      specialArgs = {
        inherit self hostName;
        inherit (inputs) brew-nix;
        username = hostConfig.username;
      };
    }
  ) configurations;

  mkHomeConfigurations = lib.mapAttrs (hostName: hostConfig:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.${hostConfig.system};
      modules = [
        ../modules/home/home-manager.nix
        {
          home = {
            username = hostConfig.username;
            homeDirectory = "/Users/${hostConfig.username}";
          };
        }
      ];
    }
  ) configurations;
in
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    apps.default = {
      type = "app";
      program = "${inputs.nix-darwin.packages.${system}.darwin-rebuild}/bin/darwin-rebuild";
    };
  };

  flake = {
    # System configurations - automatically generated for all hosts
    darwinConfigurations = mkDarwinConfigurations;

    # Home Manager configurations - automatically generated for all hosts
    homeConfigurations = mkHomeConfigurations;

    # Module exports for reusability
    nixosModules = {
      darwin = ../modules/darwin;
      home = ../modules/home;
    };

    darwinModules = {
      default = ../modules/darwin;
      homebrew = ../modules/homebrew;
      mac-host = ../hosts/darwin/mac;
    };

    homeManagerModules = {
      default = ../modules/home;
      programs = ../modules/home/programs;
    };
  };
}
