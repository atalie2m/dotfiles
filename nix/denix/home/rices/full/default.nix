{ delib, ... }:

# Home full rice mirrors host defaults, but is inheritance-only to keep
# homeConfigurations at one entry per host.
delib.rice {
  name = "full";
  inherits = [ "base" "darwin" "dev" ];
  inheritanceOnly = true;

  myconfig = { };
}
