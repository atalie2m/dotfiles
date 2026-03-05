{ delib, ... }:

# Full rice: Complete development and productivity environment
delib.rice {
  name = "full";
  inherits = [ "base" "darwin" "dev" ];

  myconfig = { };
}
