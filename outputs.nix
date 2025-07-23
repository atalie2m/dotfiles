inputs@{ self, nix-darwin, nixpkgs, home-manager, brew-nix, brew-api }:
let
  system = "aarch64-darwin";

  configuration = import ./nix/hosts/darwin/mac/configuration.nix {
    inherit nix-darwin self brew-nix;
    brewNixModule = ./nix/modules/homebrew/brew-nix;
  };

  homeConfiguration = import ./nix/modules/home/home-configuration.nix {
    inherit nixpkgs home-manager system;
  };
in
{
  darwinConfigurations."{{LOCAL_HOSTNAME}}" = configuration;
  homeConfigurations."{{LOCAL_HOSTNAME}}" = homeConfiguration;

  # Expose system for easier access
  packages.${system}.default = configuration.system;
}
