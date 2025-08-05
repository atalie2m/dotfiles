{ delib, ... }:

delib.module {
  name = "gpg";

  options.gpg = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/programs/gpg.nix ];
}
