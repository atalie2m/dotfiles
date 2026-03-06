{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.minimum;
in
# Home minimum rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "minimum";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
