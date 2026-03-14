{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.ultra;
in
# Home ultra rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "ultra";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
