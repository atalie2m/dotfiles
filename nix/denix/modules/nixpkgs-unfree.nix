{ delib, ... }:

# Allow select unfree packages on both Home Manager and Darwin

delib.module {
  name = "nixpkgs.unfree";

  options.nixpkgs.unfree = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/nixpkgs/unfree.nix ];
  darwin.always.imports = [ ../../modules/nixpkgs/unfree.nix ];
}
