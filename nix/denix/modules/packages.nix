{ delib, ... }:

delib.module {
  name = "packages";
  home.always.imports = [ ../../modules/home/packages.nix ];
}
