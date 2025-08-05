{ delib, ... }:

delib.module {
  name = "darwinFonts";
  darwin.always.imports = [ ../../modules/darwin/fonts.nix ];
}
