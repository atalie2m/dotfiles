{ delib, ... }:

# Base rice: cross-platform essentials.
delib.rice {
  name = "base";

  myconfig = {
    system.nix.enable = true;
    tools.core.enable = true;
    tools.shell.enable = true;
    tools.dev.git.enable = true;
    tools.security.enable = true;
  };
}
