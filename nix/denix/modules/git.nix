{ delib, ... }:

delib.module {
  name = "git";
  home.always.imports = [ ../../modules/home/programs/git.nix ];
}
