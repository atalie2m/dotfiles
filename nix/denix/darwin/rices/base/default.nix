{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.base;
in
# Base rice: cross-platform essentials.
delib.rice {
  name = "base";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}
