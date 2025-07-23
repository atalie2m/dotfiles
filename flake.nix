{
  description = "Atalie's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  let
    system = "aarch64-darwin";

    configuration = nix-darwin.lib.darwinSystem {
      modules = import ./nix;
      specialArgs = { inherit self; };
    };

    homeConfiguration = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [
        ./nix/home-manager.nix
      ];
    };
  in
  {
    darwinConfigurations."{{LOCAL_HOSTNAME}}" = configuration;
    homeConfigurations."{{LOCAL_HOSTNAME}}" = homeConfiguration;

    # Expose system for easier access
    packages.${system}.default = configuration.system;
  };
}
