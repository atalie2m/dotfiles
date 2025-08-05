{ delib, ... }:

delib.module {
  name = "karabiner";

  options.karabiner = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/karabiner.nix ];
}
