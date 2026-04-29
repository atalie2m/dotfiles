{ dotmod, config, lib, ... }:

# Allow select unfree packages on the Darwin package set shared with Home Manager.

let
  mkAllowUnfreePredicate = cfg:
    if cfg.allowAll
    then (_: true)
    else (pkg: lib.elem (lib.getName pkg) cfg.packages);
in

(dotmod.mkModule { inherit config; }) {
  path = "nixpkgs.unfree";

  options = with dotmod; {
    enable = boolOption false;
    allowAll = boolOption false;
    packages = listOfOption str [ ];
  };

  darwinOnEnable = { cfg, ... }: {
    nixpkgs.config.allowUnfreePredicate = mkAllowUnfreePredicate cfg;
  };
}
