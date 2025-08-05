{ delib, ... }:

delib.module {
  name = "zsh";
  home.always.imports = [ ../../modules/home/shells/zsh.nix ];
}
