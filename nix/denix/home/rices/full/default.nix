{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.full;
in
# Home full rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "full";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
