{ nixpkgs, home-manager, system }:

home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.${system};
  modules = [
    ./home-manager.nix
  ];
}
