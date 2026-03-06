{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.minimum;
in
# Minimum rice: compatibility alias for the base profile.
delib.rice {
  name = "minimum";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}
