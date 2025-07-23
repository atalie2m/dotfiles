{ nix-darwin, self }:

nix-darwin.lib.darwinSystem {
  modules = import ./default.nix;
  specialArgs = { inherit self; };
}
