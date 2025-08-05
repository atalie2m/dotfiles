{ delib, ... }:

delib.module {
  name = "starship";
  home.always.imports = [ ../../modules/home/programs/starship.nix ];
}
