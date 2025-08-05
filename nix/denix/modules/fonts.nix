{ delib, ... }:

delib.module {
  name = "fonts";
  home.always.imports = [ ../../modules/home/fonts.nix ];
}
