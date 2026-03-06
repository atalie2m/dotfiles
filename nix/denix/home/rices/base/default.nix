{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.base;
in
# Home base rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "base";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
