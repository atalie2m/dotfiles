{ delib, ... }:

delib.module {
  name = "nixpkgsUnfree";
  home.always.imports = [ ../../modules/nixpkgs/unfree.nix ];
  darwin.always.imports = [ ../../modules/nixpkgs/unfree.nix ];
}
