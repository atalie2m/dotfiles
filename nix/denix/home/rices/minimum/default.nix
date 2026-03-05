{ delib, ... }:

# Home minimum rice mirrors host defaults, but is inheritance-only to keep
# homeConfigurations at one entry per host.
delib.rice {
  name = "minimum";
  inherits = [ "base" ];
  inheritanceOnly = true;

  myconfig = { };
}
