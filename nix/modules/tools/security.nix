{ delib, ... }:

# Security tool group

delib.module {
  name = "tools.security";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}
