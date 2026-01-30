{ delib, ... }:

# System integration tool group

delib.module {
  name = "tools.system";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}
