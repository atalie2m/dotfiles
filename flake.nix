{
  description = "Atalie's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    system = "aarch64-darwin";
    configuration = nix-darwin.lib.darwinSystem {
      modules = import ./nix;
      specialArgs = { inherit self; };
    };
  in
  {
    darwinConfigurations."{{LOCAL_HOSTNAME}}" = configuration;

    # Expose system for easier access
    packages.${system}.default = configuration.system;
  };
}
