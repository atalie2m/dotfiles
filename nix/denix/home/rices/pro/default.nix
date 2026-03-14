{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.pro;
in
# Home pro rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "pro";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
