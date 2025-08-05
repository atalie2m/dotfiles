{ delib, ... }:

delib.module {
  name = "terminal";

  home.always.imports = [ ../../modules/home/programs/terminals.nix ];
}
