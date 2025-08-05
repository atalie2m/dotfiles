{ delib, ... }:

delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  darwin = { ... }: {
    # Temporarily disabled to isolate recursion issue
    # imports = [ ../../modules/brew-nix.nix ];
  };
}
