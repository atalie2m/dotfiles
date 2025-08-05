{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  darwin = { name, cfg, myconfig, ... }: {
    imports = [
      ../../../modules/homebrew/default.nix
    ];
  };
}
