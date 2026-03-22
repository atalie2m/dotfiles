{ delib, lib, ... }:

# Allow select unfree packages on both Home Manager and Darwin

let
  mkAllowUnfreePredicate = cfg:
    if cfg.allowAll
    then (_: true)
    else (pkg: lib.elem (lib.getName pkg) cfg.packages);
in

delib.module {
  name = "nixpkgs.unfree";

  options.nixpkgs.unfree = with delib.options; {
    enable = boolOption false;
    allowAll = boolOption false;
    packages = listOfOption str [ ];
  };

  home.ifEnabled = { cfg, ... }: {
    nixpkgs.config.allowUnfreePredicate = mkAllowUnfreePredicate cfg;
  };

  darwin.ifEnabled = { cfg, ... }: {
    nixpkgs.config.allowUnfreePredicate = mkAllowUnfreePredicate cfg;
  };
}
