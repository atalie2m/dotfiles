{ delib, ... }:
let
  modules = import ../../modules.nix { inherit delib; };
in
delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  darwin.imports = with delib.modules; [
    homebrew
    darwinFonts
  ];
}
