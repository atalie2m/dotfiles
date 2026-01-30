{ delib, ... }:

# Shell tool group

delib.module {
  name = "tools.shell";

  options = with delib; moduleOptions {
    enable = boolOption false;
    manageSystemShells = boolOption false;
    defaultShell = strOption "zsh";
    extraAliases = attrsOption {};
  };
}
