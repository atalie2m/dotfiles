{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.partial;
in
# Home partial rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "partial";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
