{ delib, ... }:

delib.module {
  name = "gpg";
  home.always.imports = [ ../../modules/home/programs/gpg.nix ];
}
