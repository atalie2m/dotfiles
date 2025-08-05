{ delib, ... }:

delib.module {
  name = "git";

  options.git = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../modules/home/programs/git.nix ];
}
