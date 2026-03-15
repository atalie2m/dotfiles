{ delib, ... }:

# Home minimum rice mirrors host defaults, but is inheritance-only to keep
# Retained as an in-repo composition tree; not exported from the root flake.
delib.rice {
  name = "minimum";
  inherits = [ "base" ];
  inheritanceOnly = true;
  myconfig = { };
}
