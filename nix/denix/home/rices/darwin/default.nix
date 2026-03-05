{ delib, ... }:

# Home darwin rice mirrors host defaults, but is inheritance-only to keep
# homeConfigurations at one entry per host.
delib.rice {
  name = "darwin";
  inherits = [ "base" ];
  inheritanceOnly = true;

  myconfig = {
    tools.system.nixHomebrew.enable = true;
    tools.system.homebrewNative.enable = true;
    tools.system.hostnames.enable = true;
    tools.system.fonts.enable = true;
  };
}
