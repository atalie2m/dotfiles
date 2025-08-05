{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  darwin = { name, cfg, myconfig, ... }: {
    imports = [ 
      # Disabled brew-nix due to module not being available in denix context
      # ../../../modules/homebrew/default.nix
      ../../../modules/darwin/fonts.nix
    ];
  };
}
