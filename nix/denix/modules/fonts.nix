{ delib, ... }:

# Fonts configuration shared across platforms

delib.module {
  name = "fonts";

  options.fonts = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/fonts.nix ];
  darwin.always.imports = [ ../../modules/darwin/fonts.nix ];
}
