{ delib, ... }:

# Minimum rice: compatibility alias for the base profile.
delib.rice {
  name = "minimum";
  inherits = [ "base" ];

  myconfig = { };
}
