{ delib, ... }:

delib.module {
  name = "homebrew";
  darwin.always.imports = [ ../../modules/homebrew/default.nix ];
}
