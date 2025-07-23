{ nix-darwin, self }:

nix-darwin.lib.darwinSystem {
  modules = import ../.;
  specialArgs = { inherit self; };
}
