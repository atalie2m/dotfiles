{ delib, ... }:

delib.module {
  name = "bash";

  options.bash = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/shells/bash.nix ];
}
