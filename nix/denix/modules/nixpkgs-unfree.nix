{ delib, lib, ... }:

# Allow select unfree packages on both Home Manager and Darwin

delib.module {
  name = "nixpkgs.unfree";

  options.nixpkgs.unfree = with delib.options; {
    enable = boolOption false;
    packages = listOfOption str [ "claude-code" ];
  };

  home.ifEnabled = { cfg, ... }: {
    nixpkgs.config.allowUnfreePredicate = pkg: lib.elem (lib.getName pkg) cfg.packages;
  };

  darwin.ifEnabled = { cfg, ... }: {
    nixpkgs.config.allowUnfreePredicate = pkg: lib.elem (lib.getName pkg) cfg.packages;
  };
}
