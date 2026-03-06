{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.dev;
in
# Home dev rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "dev";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}
