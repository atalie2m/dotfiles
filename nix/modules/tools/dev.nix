{ delib, ... }:

# Development tool group

delib.module {
  name = "tools.dev";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}
