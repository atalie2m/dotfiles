{ delib, ... }:

delib.module {
  name = "karabiner";
  home.always.imports = [ ../../modules/home/karabiner.nix ];
}
