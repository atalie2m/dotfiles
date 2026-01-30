{ delib, ... }:

# Terminal tool group

delib.module {
  name = "tools.terminal";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}
