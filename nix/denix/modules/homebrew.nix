{ delib, ... }:

delib.module {
  name = "homebrew";

  options.homebrew = with delib.options; {
    enable = boolOption false;
  };

  darwin.always.imports = [ ../../modules/homebrew/default.nix ];
}
