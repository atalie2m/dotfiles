{ delib, ... }:

delib.module {
  name = "terminal";

  options.terminal = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/programs/terminals.nix ];
}
