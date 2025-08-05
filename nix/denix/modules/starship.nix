{ delib, ... }:

delib.module {
  name = "starship";

  options.starship = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/programs/starship.nix ];
}
