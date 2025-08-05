{ delib, ... }:

delib.module {
  name = "zsh";

  options.zsh = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/shells/zsh.nix ];
}
