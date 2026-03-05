{ delib, ... }:

# Home base rice mirrors host defaults, but is inheritance-only to keep
# homeConfigurations at one entry per host.
delib.rice {
  name = "base";
  inheritanceOnly = true;

  myconfig = {
    system.nix.enable = true;
    tools.core.enable = true;
    tools.shell.enable = true;
    tools.dev.git.enable = true;
    tools.security.enable = true;
  };
}
