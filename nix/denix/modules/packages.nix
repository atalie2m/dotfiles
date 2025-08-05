{ delib, ... }:

delib.module {
  name = "packages";

  options.packages = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/packages.nix ];
}
