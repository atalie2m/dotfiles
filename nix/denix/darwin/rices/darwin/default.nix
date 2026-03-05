{ delib, ... }:

# Darwin rice: macOS-specific base integrations.
delib.rice {
  name = "darwin";
  inherits = [ "base" ];

  myconfig = {
    tools.system.nixHomebrew.enable = true;
    tools.system.homebrewNative.enable = true;
    tools.system.hostnames.enable = true;
    tools.system.fonts.enable = true;
  };
}
