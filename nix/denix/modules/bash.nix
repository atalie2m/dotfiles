{ delib, ... }:

delib.module {
  name = "bash";
  home.always.imports = [ ../../modules/home/shells/bash.nix ];
}
