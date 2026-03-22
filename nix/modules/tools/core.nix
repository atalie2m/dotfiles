{ delib, ... }:

# Core CLI tool group

delib.module {
  name = "tools.core";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}
